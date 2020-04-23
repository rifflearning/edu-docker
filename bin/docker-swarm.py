#!/usr/bin/env python3

# docker-swarm.py
# author: Michael Jay Lippert mike@rifflearning.com
# Command line tool for managing docker swarms in the AWS cloud

import time
import json
import re
import sys
import os
import signal
import subprocess

import boto3
from botocore.exceptions import ClientError, ParamValidationError
import click
import psutil

click_region_option = click.option('--region', type=click.Choice(['us-east-1',
                                                                  'us-east-2',
                                                                  'us-west-1',
                                                                  'us-west-2',
                                                                  'eu-west-1',
                                                                  'eu-west-2']),
                                   default='us-east-2', show_default=True,
                                   help='The AWS region name where the docker swarm will be deployed.')


def _highlight(x, fg='green'):
    """Write to the console, highlighting the text in green (by default)

    _highlight will also convert any object not a string to a json string
    and write that instead.
    """
    if not isinstance(x, str):
        x = json.dumps(x, sort_keys=True, indent=2)
    click.secho(x, fg=fg)


def _get_stack_manager_instances(stack_name, region):
    """Get the IP addresses of all manager nodes of a docker swarm created by the named cloudformation Stack

    returns a list of manager node instance dicts containing the id and ip of the instance
    """
    try:
        # To get the manager instances, we find the manager autoscaling group and get the
        # instances from it, then look up that instance and get its IP. (The ASG is responsible
        # for creating an new instance if one fails, so that the desired number of managers
        # exist in the swarm, and similarly for the worker nodes)
        cloudformation = boto3.client('cloudformation', region_name=region)
        autoscaling = boto3.client('autoscaling', region_name=region)
        ec2 = boto3.client('ec2', region_name=region)

        # get the Manager ASG ID
        mgr_asg_srd = cloudformation.describe_stack_resource(StackName=stack_name, LogicalResourceId='ManagerAsg')
        mgr_asg_id = mgr_asg_srd['StackResourceDetail']['PhysicalResourceId']

        # get the manager instance IDs
        mgr_instances = autoscaling.describe_auto_scaling_groups(AutoScalingGroupNames=[mgr_asg_id])['AutoScalingGroups'][0]['Instances']
        mgr_instance_ids = [ instance['InstanceId'] for instance in mgr_instances ]
        #click.echo('mgr_instance_ids: {resp}'.format(resp=mgr_instance_ids))

        # get the manager instance IPs
        reservations = ec2.describe_instances(InstanceIds=mgr_instance_ids)['Reservations']

        # extract the instance id and ip from the instances of all returned reservations
        #   Note: a reservation in this situation is a request to start a group of instances
        #         see https://serverfault.com/questions/749118/aws-ec2-what-is-a-reservation-id-exactly-and-what-does-it-represent
        instances = [{'id': inst['InstanceId'],
                      'ip': inst['PublicIpAddress'],
                      'dns': inst['PublicDnsName'],
                     }
                     for res in reservations for inst in res['Instances']]
    except ClientError as e:
        _highlight('{code}: {msg}'.format(code=e.response['Error']['Code'], msg=e.response['Error']['Message']), fg='red')
        instances = []

    return instances


def _get_stack_status(stack_name, region):
    """
    Returns the stack status which will be one of:
        'CREATE_IN_PROGRESS'
        'CREATE_FAILED'
        'CREATE_COMPLETE'
        'ROLLBACK_IN_PROGRESS'
        'ROLLBACK_FAILED'
        'ROLLBACK_COMPLETE'
        'DELETE_IN_PROGRESS'
        'DELETE_FAILED'
        'DELETE_COMPLETE'
        'UPDATE_IN_PROGRESS'
        'UPDATE_COMPLETE_CLEANUP_IN_PROGRESS'
        'UPDATE_COMPLETE'
        'UPDATE_ROLLBACK_IN_PROGRESS'
        'UPDATE_ROLLBACK_FAILED'
        'UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS'
        'UPDATE_ROLLBACK_COMPLETE'
        'REVIEW_IN_PROGRESS'

        cloudformation exceptions will be raised, in particular ClientError
        when the given stack_name does not exist.
    """
    cloudformation = boto3.client('cloudformation', region_name=region)
    stack = cloudformation.describe_stacks(StackName=stack_name)['Stacks'][0]
    return stack['StackStatus']


def _get_tunnel_info(port):
    """Get info on any running ssh tunnel processes using the given local port

    Each process gets: { 'pid', 'ip' }
    """
    # [bind_address:]port:remote_socket
    bind_re = re.compile('(?P<bind_address>.*):(?P<port>.*):(?P<remote_socket>.*)')
    # remote_user@remote_ip
    user_ip_re = re.compile('(?P<remote_user>.*)@(?P<remote_ip>.*)')

    # This is an example of what the tunnel process(es) info from psutil look like:
    # {'name': 'ssh',
    #  'pid': 26332,
    #  'exe': '/usr/bin/ssh',
    #  'username': 'mjl',
    #  'cmdline': ['ssh', '-f', '-NL', 'localhost:2374:/var/run/docker.sock', 'docker@18.191.218.147']
    # }

    def is_tunnel_proc(pinfo):
        """Test if a process is an ssh tunnel using given port
        """
        if pinfo['name'] != 'ssh':
            return False
        if len(pinfo['cmdline']) < 5:
            return False
        if pinfo['cmdline'][-3] != '-NL':
            return False
        bind = bind_re.fullmatch(pinfo['cmdline'][-2])
        if not (bind and bind.group('port') == str(port)):
            return False
        return True

    tunnel_info = [{'pid': int(p.info['pid']),
                    'ip': user_ip_re.fullmatch(p.info['cmdline'][-1]).group('remote_ip'),
                   }
                   for p in psutil.process_iter(attrs=['pid', 'name', 'cmdline']) if is_tunnel_proc(p.info)]

    return tunnel_info


def _kill(pids):
    """
    """
    for pid in pids:
        _highlight("Killing PID {}".format(pid), fg='green')
        os.kill(pid, signal.SIGKILL)


def _kill_existing_tunnels(port, **kwargs):
    """
    """
    # check if we have existing ssh tunnel processes
    tunnel_info = _get_tunnel_info(port)

    if len(tunnel_info) == 0:
        return True, 0

    tunnel_ref = 'this existing tunnel'
    if len(tunnel_info) > 1:
        _highlight('There are {cnt} existing ssh tunnels! More than one is unexpected!'.format(cnt=len(tunnel_info)))
        tunnel_ref = 'these existing tunnels'

    click.echo('\nFound {} (pid: ip addr):'.format(tunnel_ref))
    _highlight('\n'.join(['  {pid}: {ip}'.format(**info) for info in tunnel_info]))

    if 'prompt' in kwargs:
        prompt = kwargs['prompt']
    else:
        prompt = 'Kill {} (y/n)?'.format(tunnel_ref)
    kill_tunnels = click.prompt(prompt, type=bool)

    if kill_tunnels:
        _kill([tinfo['pid'] for tinfo in tunnel_info])

    return kill_tunnels, len(tunnel_info)


@click.command()
@click_region_option
@click.option('--key', 'key_name', required=True)
@click.option('--manager-count', '-m', type=int, default='3', required=True, help='Number of managers to spin up. Recommended (and default) number is 3 (from Docker for AWS) for reliability.')
@click.option('--manager-type', '-I', default='t2.micro', required=True, help='AWS Instance type for managers. Defaults to t2.micro.')
@click.option('--worker-count', '-w', type=int, default='4', required=True, help='Number of workers to spin up. Defaults to 4')
@click.option('--worker_type', '-i', default='t2.micro', required=True, help='AWS Instance type for workers. Defaults to t2.micro.')
@click.argument('stack_name', required=True)
def create(stack_name, region, key_name, manager_count, manager_type, worker_count, worker_type):
    """Create a CloudFormation stack for a docker swarm.

    A cloudformation stack name can contain only alphanumeric characters (case sensitive) and hyphens.
    It must start with an alphabetic character and cannot be longer than 128 characters.
    """
    # Cloudformation stack template to use. This is the Docker for AWS template (community edition, stable)
    template_url = 'https://editions-us-east-1.s3.amazonaws.com/aws/stable/Docker.tmpl'

    cloudformation = boto3.client('cloudformation', region_name=region)

    click.echo('Creating cloudformation stack:\n'
               '      name: {name} ; region: \'{region}\'\n'
               '       key: {key}\n'
               '  managers: {mgr_cnt} {mgr_type} instance(s)\n'
               '   workers: {wkr_cnt} {wkr_type} instance(s)\n'
               .format(name=stack_name, region=region, key=key_name,
                       mgr_cnt=manager_count, mgr_type=manager_type,
                       wkr_cnt=worker_count, wkr_type=worker_type))

    try:
        response = cloudformation.create_stack(
            StackName=stack_name,
            TemplateURL=template_url,
            Parameters=[
                { 'ParameterKey': 'KeyName',                'ParameterValue': key_name },
                { 'ParameterKey': 'ManagerSize',            'ParameterValue': str(manager_count) },
                { 'ParameterKey': 'ManagerInstanceType',    'ParameterValue': manager_type },
                { 'ParameterKey': 'ClusterSize',            'ParameterValue': str(worker_count) },
                { 'ParameterKey': 'InstanceType',           'ParameterValue': worker_type },
                { 'ParameterKey': 'ManagerDiskSize',        'ParameterValue': '20' },
                { 'ParameterKey': 'ManagerDiskType',        'ParameterValue': 'standard' },
                { 'ParameterKey': 'WorkerDiskSize',         'ParameterValue': '20' },
                { 'ParameterKey': 'WorkerDiskType',         'ParameterValue': 'standard' },
                { 'ParameterKey': 'EnableCloudWatchLogs',   'ParameterValue': 'yes' },
                { 'ParameterKey': 'EnableSystemPrune',      'ParameterValue': 'no' },
            ],
            TimeoutInMinutes=40,
            Capabilities=[ 'CAPABILITY_IAM' ],
            OnFailure='ROLLBACK'
        )
    except ClientError as e:
        _highlight('{code}: {msg}'.format(code=e.response['Error']['Code'], msg=e.response['Error']['Message']), fg='red')
        sys.exit(1)

    # This seems more debugging, not sure what a failure would look like, but I'm guessing
    # there's some exceptions that need catching (this code should be updated when that is
    # discovered)
    #click.echo('create_stack response: {resp}'.format(resp=response))


@click.command()
@click_region_option
@click.argument("stack_name", required=True)
def delete(stack_name, region):
    """Delete the CloudFormation stack(s) with the given name
    """
    cloudformation = boto3.client('cloudformation', region_name=region)

    try:
        stacks = cloudformation.describe_stacks(StackName=stack_name)['Stacks']

        _highlight('Found {cnt} stacks with the name {name}'.format(name=stack_name, cnt=len(stacks)))
        delete_stacks = click.prompt('Are you sure you want to delete these stack(s)? (y/n)', type=bool)
        if delete_stacks:
            for stack in stacks:
                _highlight("Deleting stack {}".format(stack['StackId']))
                cloudformation.delete_stack(StackName=stack['StackId'])
    except ClientError as e:
        _highlight('{code}: {msg}'.format(code=e.response['Error']['Code'], msg=e.response['Error']['Message']), fg='red')
        sys.exit(1)


@click.command()
@click_region_option
@click.argument("stack_name", required=True)
def status(stack_name, region):
    """Get the current status of an existing cloudformation stack
    """
    try:
        status = _get_stack_status(stack_name, region)
        _highlight(status)
    except ClientError as e:
        _highlight('{code}: {msg}'.format(code=e.response['Error']['Code'], msg=e.response['Error']['Message']), fg='red')
        sys.exit(1)


@click.command()
@click_region_option
@click.argument("stack_name", required=True)
def wait_for_complete(stack_name, region):
    """Wait for the stack status to be *_COMPLETE

    Wait for the stack status to become complete (any status
    ending in '_COMPLETE' is considered complete.
    """
    # how long to wait before the next check for complete (seconds)
    period = 60

    try:
        while True:
            status = _get_stack_status(stack_name, region)
            _highlight('{time}: {status}'.format(time=time.strftime('%H:%M:%S'), status=click.style(status, fg='yellow')))

            complete = status.endswith('_COMPLETE')
            if complete:
                break;

            time.sleep(period)
    except ClientError as e:
        # if waiting for delete to complete, then this is expected, but still should be reported specially just in case
        _highlight('{code}: {msg}'.format(code=e.response['Error']['Code'], msg=e.response['Error']['Message']), fg='red')


@click.command()
@click_region_option
@click.argument("stack_name", required=True)
def get_stack_dns(stack_name, region):
    """Gets the public DNS of a stack with the name stack_name

    """
    cloudformation = boto3.client('cloudformation', region_name=region)

    try:
        stack = cloudformation.describe_stacks(StackName=stack_name)['Stacks'][0]

        # The DefaultDNSTarget is one of the outputs from the Docker for AWS template we use to create the stack
        outputs = stack['Outputs']
        for o in outputs:
            if o['OutputKey'] == 'DefaultDNSTarget':
                dns = o['OutputValue']
                click.echo('\n'.join(['The {name} stack\'s public DNS is:'.format(name=stack_name),
                                      click.style('  {dns}\n'.format(dns=dns), fg='green')]))

    except ClientError as e:
        _highlight('{code}: {msg}'.format(code=e.response['Error']['Code'], msg=e.response['Error']['Message']), fg='red')


@click.command()
@click_region_option
@click.argument("stack_name", required=True)
def get_stack_manager_ips(stack_name, region):
    """Get the IP addresses of all manager nodes of a docker swarm created by the named cloudformation Stack

    Retrieves the IP addresses all manager nodes from a CloudFormation
    docker swarm Stack with the given stack_name
    """
    instances = _get_stack_manager_instances(stack_name, region)

    click.echo('manager instances:')
    _highlight('\n'.join(['  {id}: {ip}'.format(**inst) for inst in instances]))


@click.command()
@click_region_option
@click.option('-i', 'index', default=0, help='The index of manager whose ip should be returned. 0 is the index of the 1st manager')
@click.argument("stack_name", required=True)
def get_stack_manager_ip(stack_name, index, region):
    """Get the IP address of the specified manager node of a docker swarm created by the named cloudformation Stack

    Retrieves the IP address of the manager node at the specified index
    from a CloudFormation docker swarm Stack with the given stack_name
    with no extra text, so it can be used in a environment variable.
    """
    try:
        instances = _get_stack_manager_instances(stack_name, region)
        click.echo(instances[index]['ip'])
    except IndexError:
        click.echo('Only {cnt} mananger(s) found, could not get the ip of manager[{i}]'.format(i=index, cnt=len(instances)), err=True)


@click.command()
@click_region_option
@click.argument("stack_name", required=True)
def get_stack_manager_dns(stack_name, region):
    """Get the DNS addresses of all manager nodes of a docker swarm created by the named cloudformation Stack

    Retrieves the DNS addresses all manager nodes from a CloudFormation
    docker swarm Stack with the given stack_name
    """
    instances = _get_stack_manager_instances(stack_name, region)

    click.echo('manager instances:')
    _highlight('\n'.join(['  {id}: {dns}'.format(**inst) for inst in instances]))


@click.command()
@click.option('--key', 'key_name',
              help='The full path to the AWS key file for the docker swarm. If unspecified, '
                   'the key must be associated with the node\'s IP address in ~/.ssh/config')
@click_region_option
@click.argument("stack_name", required=True)
def tunnel(stack_name, region, key_name):
    """Create a tunnel to a docker swarm manager node of a cloudformation stack

    An ssh tunnel to a selected manager node will be created. If there is more
    than one manager node the user will be prompted to select one of them.
    If there is an existing tunnel, the user will be prompted on whether to
    replace it or abort, leaving the existing tunnel alone.
    The tunnel will always be created at localhost port 2374.
    After creating the tunnel, in order for docker to use it the evironment
    variable DOCKER_HOST must be exported pointing to the tunnel.
      export DOCKER_HOST=localhost:2374
    """
    # how to tunnel to the docker swarm manager is described at
    # https://docs.docker.com/docker-for-aws/deploy/#manager-nodes

    # There's no need at this time to allow the user or tunnel port to be configurable
    # so they are hardcoded here. This makes them easily configurable in the future if desired.
    user = 'docker'
    port = 2374

    # Check that the stack exists and that create has completed
    try:
        status = _get_stack_status(stack_name, region)
        if status != 'CREATE_COMPLETE':
            _highlight('Stack not ready. Status: {status}'.format(status=status), fg='red')
            _highlight('You can wait for it to be ready using:\n'
                       '  docker-swarm.py wait-for-complete {name} --region={region}\n\n'
                       .format(name=stack_name, region=region))
            return
    except ClientError as e:
        _highlight('{code}: {msg}'.format(code=e.response['Error']['Code'], msg=e.response['Error']['Message']), fg='red')
        return

    mgr_instances = _get_stack_manager_instances(stack_name, region)

    if len(mgr_instances) == 1:
        mgr_ip = mgr_instances[0]['ip']
    else:
        # Ask which manager to tunnel to
        _highlight('Select the manager you want to tunnel to:', fg='white')
        selection_str = '\n'.join(['  {n}) {id}: {ip}'.format(n=n + 1, id=inst['id'], ip=inst['ip'])
                                   for n, inst in enumerate(mgr_instances)])
        _highlight(selection_str)
        sel = click.prompt('Your selection', type=int)
        if sel < 1 or sel > len(mgr_instances):
            mgr_ip = mgr_instances[0]['ip']
        else:
            mgr_ip = mgr_instances[sel - 1]['ip']

    # check if we have existing ssh tunnel processes (check after selecting mgr so user sees the mgr IPs)
    kill_tunnels, tunnel_cnt = _kill_existing_tunnels(port, prompt='Do you want to kill the existing tunnel(s)\n'
                                                                   'and create a new one to {ip}? (y/n)'.format(ip=mgr_ip))

    if tunnel_cnt > 0:
        if not kill_tunnels:
            _highlight('Leaving existing tunnels and aborting creating the tunnel to {ip}.'.format(ip=mgr_ip))
            if 'DOCKER_HOST' in os.environ:
                _highlight('\nYou have DOCKER_HOST exported in your environment:\n  DOCKER_HOST={}'.format(os.environ['DOCKER_HOST']))
            else:
                _highlight('\nYou don\'t have DOCKER_HOST exported in your environment you should:\n'
                           '  export DOCKER_HOST=localhost:{}'.format(port))

            return

    # create the tunnel

    tunnel_cmd = ['ssh', '-f',
                         '-NL', 'localhost:{port}:/var/run/docker.sock'.format(port=port),
                         '{user}@{remote_ip}'.format(user=user, remote_ip=mgr_ip)]

    # if a key was supplied add it to the command
    if key_name is not None:
        tunnel_cmd[2:2] = ['-i', '{}'.format(key_name)]

    click.echo('Creating the tunnel to {ip} using cmd:\n  {cmd}'.format(cmd=click.style(' '.join(tunnel_cmd), fg='green'), ip=mgr_ip))
    ps = subprocess.Popen(tunnel_cmd, start_new_session=True,
                          stdin=subprocess.DEVNULL,
                          stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL)

    # ps.pid won't be the tunnel process's pid because ssh -f forks
    # see https://stackoverflow.com/questions/4996311/python-subprocess-popen-get-pid-of-the-process-that-forks-a-process
    # which also lets us wait for it to exit so we can check the returncode
    ssh_retcode = ps.wait()

    # if retcode is 0 all is good, otherwise (likely 255) creating the tunnel failed
    if ssh_retcode != 0:
        sys.exit('Creating the tunnel failed (ssh cmd returned {})'.format(ssh_retcode))

    click.echo('\n'.join(
        [
            '\nTo use this tunnel w/ your local docker you will need DOCKER_HOST set',
            'appropriately in your environment. Set it with the command:',
            click.style('  export DOCKER_HOST=localhost:{port}\n'.format(port=port), fg='cyan'),
        ]))


@click.command()
def kill_tunnel():
    """Kill running tunnels to docker swarm manager nodes
    """
    port = 2374
    kill_tunnel, tunnel_cnt = _kill_existing_tunnels(port)

    if kill_tunnel and tunnel_cnt > 0:
        if 'DOCKER_HOST' in os.environ:
            _highlight('\nYou have DOCKER_HOST exported in your environment:\n'
                       '  DOCKER_HOST={}\n'
                       'You can remove it using:\n'
                       '  unset DOCKER_HOST\n'.format(os.environ['DOCKER_HOST']))
    else:
        # did not kill a tunnel
        sys.exit(1)


@click.group()
def cli():
    """Create, manage, and connect to CloudFormation stacks.

    Specifically tailored to use the Docker for AWS CloudFormation template:

    https://editions-us-east-1.s3.amazonaws.com/aws/stable/Docker.tmpl

    Basic usage:

    > create_docker_stack name size

    > ssh_stack_manager name -i path/to/keyfile.pem -u docker

    Use `cloudformation.py tunnel --help` to learn how to open a tunnel to your
    cloudformation stack to deploy a docker-compose project.

    """
    pass

cli.add_command(create)
cli.add_command(delete)
cli.add_command(status)
cli.add_command(wait_for_complete)
cli.add_command(tunnel)
cli.add_command(kill_tunnel)
cli.add_command(get_stack_dns)
cli.add_command(get_stack_manager_ips)
cli.add_command(get_stack_manager_dns)
cli.add_command(get_stack_manager_ip)

if __name__ == "__main__":
    cli(obj={})
