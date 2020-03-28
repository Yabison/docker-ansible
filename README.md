# Docker Ansible  Image

A Docker image for playing with Ansible with the following software installed:

* **Ansible**
* **awscli** : AWS Command Line Interface
* **boto/boto3** :The AWS SDK for Python
* **govmomi** : A Go library for interacting with VMware vSphere APIs (ESXi and/or vCenter).
* **sshto** : Small bash script to manage your ssh connections
* **xssh/xpanes** : xpanes/tmux  Ultimate terminal divider powered by tmux ; with Host selection via Ansible host pattern matching.

Ansible collections installed :

* **fortinet.fortios** : A collection of Ansible Modules for FortiOS
* **cisco.meraki** : An Ansible collection for managing the Cisco Meraki Dashboard
* **cisco.aci** : An Ansible collection for managing Cisco ACI infrastructure


## Tools 

### xssh

**xssh** [options] <host pattern>

Starts a xpanes session based on Ansible inventory.

> **Options**:
>  -h                Show help
> -l \<limit>       limit selected hosts to an additional pattern
>  -c \<command>     command to execute on all hosts

You can use the ENV variable $ANSIBLE_INVENTORY to precise the inventory file 

The default inventory is defined in the script /usr/local/bin/xssh [ /home/devops/ansible/inventories/production/hosts.yml]

## Docker Hub

This image is published to [Docker Hub](https://hub.docker.com/r/contentwisetv/ansible-aws/) via automated build.

## License

Author: Hervé Tamet <h.tamet@yabison.com>

Licensed under the Apache License V2.0. See the [LICENSE file](LICENSE) for details.
