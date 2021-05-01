#!/bin/bash
if [ -f /home/devops/.motderror ]; then rm /home/devops/.motderror ; fi;
if [ ! -f "/etc/ansible/.vault_password" ]; then
    echo "You need a password to decrypt, perhaps your docker-compose configuration">>  /home/devops/.motderror;
    echo "not set the file  /etc/ansible/.vault_password">>  /home/devops/.motderror;
    echo  "check the volume on docker-compose.yml">>  /home/devops/.motderror; 

    echo "You need a password to decrypt, perhaps your docker-compose configuration">>  /home/devops/.motderror;
    echo "not set the file  /etc/ansible/.vault_password ">>  /home/devops/.motderror;
    echo "check the volume definition in  docker-compose.yml">>  /home/devops/.motderror;
      
    echo "  volumes:">>  /home/devops/.motderror;
    echo "   - ./ansible:/home/devops/ansible">>  /home/devops/.motderror;
    echo "   - ./../.vault_password_xxx.txt:/etc/ansible/.vault_password">>  /home/devops/.motderror;
    > /home/devops/.motderror
else 
    if [ -f "/home/devops/.ssh/id_rsa.vault" ] ; then 
        echo "decrypt key id_rsa.vault"
        ansible-vault decrypt /home/devops/.ssh/id_rsa.vault       
        mv /home/devops/.ssh/id_rsa.vault /home/devops/.ssh/id_rsa
        chmod 600  /home/devops/.ssh/id_rsa
    fi
    if [ -f "/home/devops/.ssh/id_rsa_root.vault" ] ; then 
        echo "decrypt key"
        ansible-vault decrypt /home/devops/.ssh/id_rsa_root.vault       
        mv /home/devops/.ssh/id_rsa_root.vault /home/devops/.ssh/id_rsa_root
        chmod 600  /home/devops/.ssh/id_rsa_root
    fi
    if [ -f "/home/devops/ansible/inventories/production/group_vars/vault.yml" ] ; then 
        echo "decrypt /home/devops/ansible/inventories/production/group_vars/vault.yml"
        ansible-vault decrypt /home/devops/ansible/inventories/production/group_vars/vault.yml
    fi
fi 
#/home/devops/generate_ssh_configs.sh
ansible-galaxy install --ignore-errors -r /home/devops/ansible/.requirements.git.yml
exec "$@"