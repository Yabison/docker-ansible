# Docker Ansible  Image

A Docker image for playing with Ansible with the following software installed:

* **Ansible**
* **awscli** : AWS Command Line Interface
* **boto/boto3** :The AWS SDK for Python
* **govmomi** : A Go library for interacting with VMware vSphere APIs (ESXi and/or vCenter).
* **sshto** : Small bash script to manage your ssh connections

Ansible collections installed :

* **fortinet.fortios** : A collection of Ansible Modules for FortiOS
* **cisco.meraki** : An Ansible collection for managing the Cisco Meraki Dashboard
* **cisco.aci** : An Ansible collection for managing Cisco ACI infrastructure

## Docker Hub

This image is published to [Docker Hub](https://hub.docker.com/r/contentwisetv/ansible-aws/) via automated build.

## License

Author: Hervé Tamet <h.tamet@yabison.com>

Licensed under the Apache License V2.0. See the [LICENSE file](LICENSE) for details.
