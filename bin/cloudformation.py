#!/usr/bin/env python3

# cloudformation.py
# author: Dan Calacci dan@rifflearning.com
# Command line tool for managing cloudformation Docker deployments.

import sys
import psutil
import time
import signal
import os
import click
import subprocess
import json
import boto3
import click_completion

# add code completion
click_completion.init()

def _highlight(x, fg='green'):
    if not isinstance(x, str):
        x = json.dumps(x, sort_keys=True, indent=2)
    click.secho(x, fg=fg)


@click.command()
@click.argument("stack_name", required=True)
@click.argument("key_name", required=True)
@click.option("cluster_size", "-s", default="4", required=True, help="Number of workers to spin up. Defaults to 4")
@click.option("manager_size", "-m", default="3", required=True, help="Number of managers to spin up. Recommended (and default) number is 3 (from Docker for AWS) for reliability.")
@click.option("instance_type", "-i", default="t2.micro", required=True, help="AWS Instance type for workers. Defaults to t2.micro.")
@click.option("manager_type", "-I", default="t2.micro", required=True, help="AWS Instance type for managers. Defaults to t2.micro.")
@click.option("template_url", "-t", default="https://editions-us-east-1.s3.amazonaws.com/aws/stable/Docker.tmpl",
              required=True,
              help="Cloudformation stack template to use. Defaults to Docker for AWS template (community edition, stable)")
def create_docker_stack(stack_name, key_name, cluster_size, manager_size, instance_type, manager_type, template_url):
    """Create a Cloudformation docker stack using the template at:

    https://editions-us-east-1.s3.amazonaws.com/aws/stable/Docker.tmpl

    with the given stack_name and cluster_size.

    """
    create_stack_cmd = """
    aws cloudformation create-stack  \
    --template-url {6} \
    --stack-name {0} \
    --capabilities CAPABILITY_IAM \
    --parameters ParameterKey=ClusterSize,ParameterValue={1} \
    ParameterKey=EnableCloudWatchLogs,ParameterValue=yes \
    ParameterKey=EnableSystemPrune,ParameterValue=no \
    ParameterKey=InstanceType,ParameterValue={2} \
    ParameterKey=KeyName,ParameterValue={3} \
    ParameterKey=ManagerDiskSize,ParameterValue=20 \
    ParameterKey=ManagerDiskType,ParameterValue=standard \
    ParameterKey=ManagerInstanceType,ParameterValue={4} \
    ParameterKey=ManagerSize,ParameterValue={5} \
    ParameterKey=WorkerDiskSize,ParameterValue=20 \
    ParameterKey=WorkerDiskType,ParameterValue=standard
    """.format(stack_name, cluster_size, instance_type, key_name, manager_type, manager_size, template_url)

    #print(create_stack_cmd)
    ps = subprocess.Popen(create_stack_cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    stat = ps.poll()
    while stat == None:
        stat = ps.poll()
    if stat == 0:
        jsonS, _ = ps.communicate()
        d = json.loads(jsonS.decode('utf8'))
        stack_id = d['StackId']
        _highlight("Created stack.")
        _highlight("Stack ID: {}".format(stack_id))
        print("Run: \n\tcloudformation stack_status {}\nTo check on creation status.".format(stack_name))
        return stack_id
    else:
        _highlight("Failed to create stack", fg='red')
        print("Error:")
        print(ps.stderr.read().decode('utf8'))

@click.command()
@click.argument("stack_name", required=True)
def stack_status(stack_name):
    client = boto3.client('cloudformation')
    d = client.describe_stacks(StackName=stack_name)
    status = d['Stacks'][0]['StackStatus']
    print(status)
    return status

@click.command()
@click.argument("stack_name", required=True)
def delete_stack(stack_name):
    client = boto3.client('cloudformation')
    d = client.describe_stacks(StackName=stack_name)
    for stack in d['Stacks']:
        _highlight("Deleting stack {}".format(stack['StackId']))
        client.delete_stack(StackName=stack['StackId'])



@click.command()
@click.argument("stack_name", required=True)
def get_stack_dns(stack_name):
    """Gets the public DNS of a stack with the name stack_name

    """
    client = boto3.client('cloudformation')
    d = client.describe_stacks(StackName=stack_name)
    o = d['Stacks'][0]['Outputs']
    r = [obj for obj in o if obj['OutputKey'] == 'DefaultDNSTarget']
    print(r[0]['OutputValue'])
    return r[0]['OutputValue']

@click.command()
@click.argument("stack_name", required=True)
def get_stack_manager_ip(stack_name):
    """Retrieves the IP address of a chosen manager node from a Cloudformation Stack
    with name stack_name

    """
    client = boto3.client('cloudformation')
    d = client.describe_stack_resources(StackName=stack_name)['StackResources']
    manager_asg = [r for r in d if r['LogicalResourceId'] == 'ManagerAsg'][0]['PhysicalResourceId']
    asg_client = boto3.client('autoscaling')
    d = asg_client.describe_auto_scaling_groups(AutoScalingGroupNames=[manager_asg])
    manager_instances = d['AutoScalingGroups'][0]['Instances']
    instance_string = "\n".join(["\t{0}) {1}".format(n, i['InstanceId']) for n, i in enumerate(manager_instances)])
    _highlight("Instance IDs:\n {}".format(instance_string))
    instance_id = manager_instances[click.prompt('Enter the instance index', type=int)]['InstanceId']
    ec2 = boto3.resource('ec2')
    manager_ip = ec2.Instance(instance_id).public_ip_address
    _highlight("Manager IP: {}".format(manager_ip))
    return manager_ip

@click.command()
@click.argument("stack_name", required=True)
@click.option("--key", "-i", default="", help="Path to SSH keyfile")
@click.option("--user", "-u", default="docker", help="Username to use to SSH")
@click.pass_context
def ssh_stack_manager(ctx, stack_name, key, user):
    """SSH to a manager node of a Cloudformation stack with given name stack_name

    """
    #ctx.forward(get_stack_manager_ip)
    manager_ip = ctx.invoke(get_stack_manager_ip, stack_name=stack_name)
    #manager_ip = ctx.invoke(get_stack_manager_ip, content=ctx.forward(stack_name))
    if (key == ""):
        cmd = ["tmux", "-c", "ssh {}@{}".format(user, manager_ip)]
    else:
        cmd = ["tmux", "-c", "ssh -i {} {}@{}".format(key, user, manager_ip)]
    print(">> connecting using: ", cmd)
    subprocess.call(cmd)


def _get_tunnel_pids(port):
    try:
        tunnel_pid = subprocess.check_output(['pgrep', '-f', 'ssh.*{}:/var/run/docker.sock'.format(port)])
    except subprocess.CalledProcessError:
        return []
    pids = tunnel_pid.decode('utf-8').split("\n")

    # there's always an extra newline
    pids = [pid for pid in pids if pid != '']
    return pids

def killtunnel(port):
    tunnel_pids = _get_tunnel_pids(port)
    tunnel_pids = map(int, tunnel_pids)
    for pid in tunnel_pids:
        _highlight("Killing PID {}".format(pid), fg='green')
        os.kill(pid, signal.SIGKILL)

@click.command()
@click.argument("stack_name", required=True)
@click.option("--port", "-p", default=2374, help="Port tunnel is on")
@click.pass_context
def kill_tunnel(ctx, stack_name, port):
    existing_tunnels = _get_tunnel_pids(port)
    if len(existing_tunnels) > 0:
        _highlight("Found {} existing SSH tunnels with PIDs {}".format(
            len(existing_tunnels),
            ", ".join(existing_tunnels)), fg='red')
        kill_tunnels = click.prompt('Do you want to kill existing tunnels? (y/n)', type=bool)
        if (kill_tunnels):
            killtunnel(port)
    else:
        _highlight("No existing docker tunnel ssh processes found.")

@click.command()
@click.argument("stack_name", required=True)
@click.option("--key", "-i", default="", help="Path to SSH keyfile")
@click.option("--user", "-u", default="docker", help="Username to use to SSH")
@click.option("--port", "-p", default="2374", help="Port to tunnel")
@click.pass_context
def tunnel(ctx, stack_name, key, user, port):
    """Creates an SSH tunnel to the stack with stack_name to use a selected manager
    node for all docker commands in this shell.

    To drop the tunnel and reset your docker env, run `cloudformation.py kill_tunnel`.

    """
    # how to tunnel to the docker swarm manager is described at
    # https://docs.docker.com/docker-for-aws/deploy/#manager-nodes

    status = ctx.invoke(stack_status, stack_name=stack_name)
    if status != 'CREATE_COMPLETE':
        _highlight("Stack not ready. Status: {}".format(status), fg='red')
        print("Wait for stack to be completely created.")
        sys.exit()
    manager_ip = ctx.invoke(get_stack_manager_ip, stack_name=stack_name)

    # check if we have existing processes with this ssh tunnel
    existing_tunnels = _get_tunnel_pids(port)
    if len(existing_tunnels) > 0:
        _highlight("Found {} existing SSH tunnels with PIDs {}".format(
            len(existing_tunnels),
            ", ".join(existing_tunnels)), fg='red')
        kill_tunnels = click.prompt('Do you want to kill existing tunnels? (y/n)', type=bool)
        if (kill_tunnels):
            killtunnel(port)
    else:
        _highlight("No existing docker tunnel ssh processes found. Continuing to tunnel...")


    c = click.prompt('Continue tunneling? (y/n)', type=bool)
    if not c:
        print("Exiting!")
        return

    if (key == ""):
        cmd = ["ssh", "-f", "-NL", "localhost:{}:/var/run/docker.sock".format(port), "{}@{}".format(user, manager_ip)]
    else:
        cmd = ["ssh", "-i", "{}".format(key),  "-f", "-NL", "localhost:{}:/var/run/docker.sock".format(port), "{}@{}".format(user, manager_ip)]
    cmd = " ".join(cmd)
    print(">> tunneling using: ", cmd)


    ps = subprocess.Popen(cmd,
                          universal_newlines=True,
                          shell=True,
                          stdout=subprocess.PIPE,
                          stdin=subprocess.PIPE,
                          stderr=subprocess.STDOUT)

    stat = ps.poll()
    while stat == None:
        stat = ps.poll()

    if stat == 0:
        # Unfortunately there is no direct way to get the pid of the spawned ssh process, so we'll find it
        # by finding a matching process using psutil.
        tunnel_pids = _get_tunnel_pids(port)
        print("\n")
        _highlight("Tunnel up.")
        _highlight("Matching tunnel process IDs:")
        _highlight(", ".join(tunnel_pids))
        print("To kill this tunnel, use the command kill_tunnel")
        _highlight("\n To use this tunnel with your local docker config, run:")
        print("\n\t export DOCKER_HOST=localhost:{}".format(port))
        print("\n To reset to your local environment, run:")
        print("\n\t export DOCKER_HOST=".format(port))
    else:
        raise RuntimeError('Error creating tunnel: ' + str(stat) + ' :: ' + str(ps.stdout.readlines()))

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

cli.add_command(get_stack_dns)
cli.add_command(create_docker_stack)
cli.add_command(stack_status)
cli.add_command(delete_stack)
cli.add_command(get_stack_manager_ip)
cli.add_command(ssh_stack_manager)
cli.add_command(tunnel)
cli.add_command(kill_tunnel)

if __name__ == "__main__":
    cli(obj={})
