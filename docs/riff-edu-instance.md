Creating an AWS Instance for a Riff Edu site
============================================


# Launch a new EC2 instance
Dev instances are usually located in the AWS `us-east-2` region.

1. For the base AMI from _My AMIs_ choose the latest riff-base:
    e.g. `riff-base-20-06-09`


1. Pick an instance type (`t3a.medium` works and is cheap)

1. Instance details
    - Network: select `riff-prod-vpc`
    - Auto-assign Public IP: Enable

1. Add storage:
    - change the size to 30GB
    - leave the Volume type `standard` (it's 1/2 the price of general purpose SSD)

1. No tags needed

1. Attach existing security groups
    - `ssh_MikeLippert_SG_<region>`
    - `ssh_JordanReedie_SG_<region>`
    - `webserver_SG_<region>`

1. Use a prod keypair for access

1. Give the instance a name, e.g. `RE-nexted` for an instance serving _nexted.riffedu.com_


# SSH to the new instance

e.g. assuming the IP address is `18.210.22.47` and the key used is `~/.ssh/riffprod_1_useast2_key.pem`
```
$ ssh -i ~/.ssh/riffprod_1_useast2_key.pem ubuntu@18.210.22.47
```

## Name the instance

Not required but can be nice when ssh'ing in. It will be displayed in the command prompt on the
_next_ login.
```
sudo hostnamectl set-hostname RR-<Deployment_name>
```

## Update and upgrade

```
sudo apt update
sudo apt upgrade
```

exit, reboot and ssh back in

## Store credentials for docker to pull from the Github images

Note that this stores the credentials on the instance. When this process
is enhanced so that we can create a docker tunnel to the instance, the
credentials used will be from the machine that is tunneling, which will be
better.

```console
$ docker login docker.pkg.github.com
Username: ebporter
Password: 
WARNING! Your password will be stored unencrypted in /home/ubuntu/.docker/config.json.
Configure a credential helper to remove this warning. See
https://docs.docker.com/engine/reference/commandline/login/#credentials-store

Login Succeeded
```

## General instance configuration

### Setup the .bashrc
```
cd ~
export DEPLOY_SWARM=<Deployment_name>
sed --in-place "/DEPLOY_SWARM/s/Update_.bashrc/${DEPLOY_SWARM}/" ~/.bashrc
sed --in-place "/riff.riff-docker/s/riff-docker/edu-docker/" ~/.bashrc
```

### Create .bash_aliases
Use vim to create `.bash_aliases` with the contents listed in the Files section below.


### Get the latest riff-docker repository commits checkout 
```
cd ~/riff
git clone https://github.com/rifflearning/edu-docker.git
cd edu-docker
```

## Add the necessary labels to the docker node

The docker stack configuration files use labels to appropriately distribute
containers between swarm nodes. As this setup only has a single node we will
add all the labels to the swarm node running on this instance.

```
make dev-swarm-labels
```


## Create the Docker configs for a Riff Edu Site

The config files needed are specified in `docker-stack.yml` in the `configs` section.

### Copy the unencrypted config files from your **local machine** to the instance

**Note**: I've used `ssh-add` so I don't have to keep specifying the key file.
```
scp riffdata.local-production.yml.1 \
    signalmaster.local-production.yml.2 \
    ubuntu@18.210.22.47:riff/edu-docker/config/
```

#### OR w/ ssh config file "RE-&lt;deploy>" alias entry
```
DEPLOY=<Deployment_name>
scp riffdata.local-production.yml.1 \
    signalmaster.local-production.yml.2 \
    RE-$DEPLOY:riff/edu-docker/config/
```

### Then create the docker configs on the remote instance
(using the ssh session to the instance)
```
cd config
docker config create riffdata.local-production.yml.1{,}
docker config create signalmaster.local-production.yml.2{,}
docker config ls
cd ..
```

## Create the Docker secrets for a Riff Remote Site

The secret files needed are specified in `docker-stack.${DEPLOY_SWARM}.yml` in
the `secrets` section.

### Copy the unencrypted secret files from your **local machine** to the instance

**Note**: I've used `ssh-add` so I don't have to keep specifying the key file.
```
scp <Deployment_name>.riffedu.*.1 ubuntu@18.210.22.47:riff/edu-docker/config/secret/
```

#### OR w/ ssh config file "RE-&lt;deploy>" alias entry
```
DEPLOY=<Deployment_name>
scp $DEPLOY.riffedu.*.1 RE-$DEPLOY:riff/edu-docker/config/secret/
```

### Then create the docker secrets on the remote instance
(using the ssh session to the instance)
```
cd config/secret
docker secret create $DEPLOY_SWARM.riffedu.com.crt.1{,}
docker secret create $DEPLOY_SWARM.riffedu.com.key.1{,}
docker secret ls
cd ../..
```
or try
```
for f in $DEPLOY_SWARM.*; do docker secret create $f $f; done
```

## Start the Docker services for this Riff Remote platform

```
. bin/deploy-vars
make show-env
make deploy-stack
```

Wait until you see all services running with `1/1` REPLICAS using `docker service ls`


## Edit the mattermost config.json


exit from the ssh session

## Add the Route 53 record pointing at the new instance

Get the IP address of the running instance and add a DNS record to the
Route 53 riffremote.com hosted zone.

Test that everything is working.

# Notes

## Troubleshooting Hints

If some services aren't starting/staying running, use

```
docker service ps --format="{{.Error}}" --no-trunc <service-name>
```

to see if there is an error reported. For example if you see `"No such image: docker.pkg.git…"`
that would imply that you haven't logged in w/ valid credentials to `docker.pkg.github.com`

## SSH config file entries

Setting up `~/.ssh/config` file entries like the following example can be helpful.
The `Host`/`HostName` pairs define aliases of the name to the actual IP address,
and then the `Host RR-*` entry defines values (such as the user and the private key file)
for all of those aliases.
```
# Riff Analytics Amazon Web Services (aws) riffremote.com instances
Host RR-kevin-riff
  HostName 54.90.187.124
Host RR-meet
  HostName 52.90.74.29
Host RR-mg
  HostName 52.203.201.212
Host RR-mikecardus
  HostName 54.224.125.233
Host RR-sew
  HostName 3.84.202.47
Host RR-strategyteam
  HostName 54.164.127.129

Host RR-*
  User ubuntu
  IdentityFile ~/.ssh/riffprod_1_useast1_key.pem
  IdentitiesOnly yes
  ForwardAgent yes
```

## Files

### .bash_aliases

```
# ~/.bash_aliases: executed by .bashrc

# some more ls aliases
alias ll='ls -lF'
alias lla='ll -a'
alias la='ls -A'
alias l='ls -CF'

alias e='vim'
alias md='mkdir'

# shorter format docker ps
alias docker-ps='docker ps --format='\''table {{.ID}}\t{{.Names}}\t{{.Status}}\t{{.Image}}'\'''

# run npm scripts w/o the long npm ERR: msgs
alias npmrs='npm run --silent $*'

# From the LinuxMint 16 .bashrc
# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# From Scott McCammon's comment on https://www.eriwen.com/bash/pushd-and-popd
function mypushd {
        pushd "${@}" >/dev/null;
        dirs -v;
}

function mypopd {
        popd "${@}" >/dev/null;
        dirs -v;
}

alias d='dirs -v'
alias p='mypushd'
alias o='mypopd'

```

### create-edit-cntr.sh

```
#! /bin/sh

CNTR_NAME=edit-config
CNTR_ID=$(docker container ls --all --filter="name=$CNTR_NAME" --format="{{.ID}}")
STOPPED_CNTR_ID=$(docker container ls --filter="name=$CNTR_NAME" --filter="status=exited" --format="{{.ID}}")

if [ -z "$CNTR_ID" ]; then
    echo "You will want to do the following in a new container:"
    echo "  apt update"
    echo "  apt install vim jq"
    echo "  apt clean"
    echo "  cd /root/config"
    echo "or as a single line: apt update && apt install -y vim jq && apt clean && cd ~/config"
    docker run --name $CNTR_NAME -it -v edu-stk_edu-mm-config:/root/config ubuntu bash
fi

echo "As long as you don't delete the container you can reuse it to edit the config again by:"
echo "  docker start $CNTR_NAME"
echo "  docker attach $CNTR_NAME"
echo "  use ctrl-p ctrl-q to detach and leave the container running, or just exit if you want it stopped."

```