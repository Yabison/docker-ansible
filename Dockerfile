FROM ubuntu:19.04

ENV \
  ANSIBLE_VERSION="2.9.5" \
  ANSIBLE_LINT_VERSION="4.2.0a1" \
  MOLECULE_VERSION="2.22" \
  YAMLLINT_VERSION="1.20.0" \
  GOSS_VERSION="0.3.9"

LABEL summary="Ansible deployment tools" \
  name="yabison/docker-ansible" \
  version="1.0.x" \
  maintainer="herve tamet <h.tamet@yabison.com>"

RUN mkdir /etc/ansible/


RUN apt-get update \
  && apt-get install --no-install-recommends -y software-properties-common \
  && apt-add-repository ppa:ansible/ansible \
  && apt-get update \
  && apt-get install --no-install-recommends -y openssh-client inetutils-ping vim less curl dos2unix wget unzip graphviz git jq sshpass bash bash-completion  sudo dialog locate rsync  docker  wmdocker   python3-netaddr python3 python3-pip python3-pyfg python3-pyvmomi  \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# molecule==${MOLECULE_VERSION} \
# yamllint==${YAMLLINT_VERSION} \

RUN python3 -m pip  install --upgrade pip && pip3 install setuptools
RUN python3 -m pip  install --upgrade pip && pip3 --no-cache-dir  install \
  ansible==${ANSIBLE_VERSION} \
  ansible-lint==${ANSIBLE_LINT_VERSION} \
  requests==2.20.1 \ 
  ipaddr \
  docker \ 
  docker-compose \
  awscli \
  boto \
  boto3 \
  pyvmomi \
  sphinx \
  ansible-inventory-grapher \
  fortiosapi \
  ansible-cmdb

#RUN curl -fsSL https://goss.rocks/install | GOSS_VER=v${GOSS_VERSION} sh 



#Dld and install govc
COPY ./docker_files/bin/govmomi/govc_linux_amd64 /usr/local/bin/govc
RUN chmod 755 /usr/local/bin/govc
COPY ./docker_files/bin/govmomi/govc_bash_completion /usr/share/bash-completion/completions/govc_bash_completion
COPY ./docker_files/bin/govmomi/govc_env.bash  /home/devops/.govc_env.bash
RUN chmod 755  /home/devops/.govc_env.bash
COPY ./docker_files/bin/sshto /usr/local/bin/sshto
RUN chmod 755 /usr/local/bin/sshto

RUN printf '[local]\nlocalhost\n' > /etc/ansible/host


EXPOSE 22

# Define working directory.ans  
RUN groupadd -r devops && useradd -g devops -G adm,sudo devops -m  -s /bin/bash && \
  echo "devops ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-nopasswd && chmod 640 /etc/sudoers.d/99-nopasswd


COPY ./docker_files/config/ansible.cfg /etc/ansible/ansible.cfg
RUN chmod 644  /etc/ansible/ansible.cfg && chown -R  /etc/ansible/ansible.cfg

RUN mkdir -p /usr/share/ansible_library/roles  /usr/share/ansible_library/my_modules/ /usr/share/ansible_library/my_module_utils
RUN chown -R  devops /usr/share/ansible_library/ && chmod  -R  775 /usr/share/ansible_library/
#RUN su - devops -c  "ansible-galaxy install --ignore-errors   -r /home/devops/default_requirements.yml" 
RUN chown -R  devops:devops /home/devops/

USER devops

WORKDIR /home/devops/


#COPY env variable for govc ( vmware cli)

COPY ./docker_files/config/bash_aliases /home/devops/.bash_aliases
COPY ./requirements.yml /home/devops/requirements.yml

RUN ansible-galaxy install --ignore-errors   -r /home/devops/requirements.yml

#ENTRYPOINT ["/bin/bash", "-c", "ansible-playbook \"$@\"", "--"]
# Define default command.
CMD ["/bin/bash"]