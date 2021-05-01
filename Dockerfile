#TODO ADD github CI , tgenerate 
FROM ubuntu:20.04

ARG BUILD_DATE
ARG NAME
ARG VERSION
ARG BUILD_DATE
ARG VCS_REF
ARG VCS_URL

ENV \
  VERSION="$VERSION" \
  ANSIBLE_VERSION="2.10.4" \
  ANSIBLE_LINT_VERSION="4.3.7" \
  MOLECULE_VERSION="3.2.0" \
  YAMLLINT_VERSION="1.25.0" \
  GOSS_VERSION="0.3.16"


LABEL summary=$NAME \
  name=$NAME \
  maintainer="herve tamet <h.tamet@yabison.com>" \
  version=$VERSION \
  org.label-schema.build-date=$BUILD_DATE \
  org.label-schema.name=$NAME \
  #org.label-schema.description=$NAME \
  org.label-schema.url=="https://yabison.com" \
  org.label-schema.vcs-ref=$VCS_REF \
  org.label-schema.vcs-url=$VCS_URL \
  org.label-schema.vendor="Yabison" \
  org.label-schema.version=$VERSION \
  org.label-schema.schema-version="1.0"


LABEL summary="Ansible deployment tools" \
  name="yabison/docker-ansible" \
  version="1.1.0" \
  maintainer="herve tamet <h.tamet@yabison.com>"

RUN mkdir /etc/ansible/

RUN apt-get update && \
  apt-get upgrade && \
  apt-get install --no-install-recommends -y software-properties-common && \
  apt-get install --no-install-recommends -y \
  openssh-client sshpass rsync gpg gpg-agent\
  bash bash-completion sudo \
  vim less dos2unix unzip locate tree \
  inetutils-ping  curl  wget   git  dialog && \   
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

  #&& apt-add-repository ppa:ansible/ansible \
RUN apt-add-repository ppa:greymd/tmux-xpanes && \
  apt-get update && \
   apt-get install --no-install-recommends -y \
  tmux tmux-xpanes  \
  docker  wmdocker graphviz jq \  
  python3-netaddr python3 python3-pip python3-pyfg python3-pyvmomi  &&\
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*


# molecule==${MOLECULE_VERSION} \
# yamllint==${YAMLLINT_VERSION} \

RUN python3 -m pip  install --upgrade pip && pip3 install setuptools

RUN pip3 --no-cache-dir  install \
  ansible==${ANSIBLE_VERSION} \
  ansible-lint==${ANSIBLE_LINT_VERSION} \
  requests==2.20.1 \ 
  ipaddr \
  docker \ 
  docker-compose \
  dnspython

RUN pip3 --no-cache-dir  install \
  pyvmomi \
  sphinx \
  ansible-inventory-grapher \
  ansible-cmdb

RUN pip3 --no-cache-dir  install \
  fortiosapi \
  stormshield.sns.sslclient 

RUN pip3 --no-cache-dir  install \
  awscli \
#  boto \
  boto3



#RUN curl -fsSL https://goss.rocks/install | GOSS_VER=v${GOSS_VERSION} sh 
# Install govc
COPY ./docker/bin/govmomi/govc_linux_amd64 /usr/local/bin/govc
COPY ./docker/bin/govmomi/govc_bash_completion /usr/share/bash-completion/completions/govc_bash_completion
COPY ./docker/bin/sshto /usr/local/bin/sshto
COPY ./docker/bin/xssh /usr/local/bin/xssh
RUN  set -ex && \
  chmod 755 /usr/local/bin/govc && \
  chmod 755 /usr/local/bin/xssh && \
  chmod 755 /usr/local/bin/sshto 

#Add Ignition for fedora coresos 

RUN apt-get update && apt-get -y install ca-certificates gpg && apt-get clean
RUN set -ex && \ 
  wget -O/tmp/fedora.gpg  "https://getfedora.org/static/fedora.gpg" 
#RUN gpg --import /tmp/fedora.gpg
RUN set -ex && \
  wget -O/tmp/fcct "https://github.com/coreos/fcct/releases/download/v0.6.0/fcct-x86_64-unknown-linux-gnu" \
      && chmod +x /tmp/fcct \
      && mv /tmp/fcct /usr/local/bin/

COPY ./docker/bin/ignition-validate-x86_64-linux /usr/local/bin/ignition-validate

RUN set -ex && \
  printf '[local]\nlocalhost\n' > /etc/ansible/host

EXPOSE 22

# Add Devops User
RUN set -ex && \
  groupadd -r devops && useradd -g devops -G adm,sudo devops -m -p phyto -s /bin/bash -d /home/devops && \
  echo "devops ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/99-nopasswd && chmod 640 /etc/sudoers.d/99-nopasswd

RUN  set -ex && \
  chown -R  devops:devops /home/devops/


COPY ./docker/bin/govmomi/govc_env.bash  /home/devops/.govc_env.bash
RUN  set -ex && \
  chmod 755 /home/devops/.govc_env.bash

COPY ./docker/config/ansible.cfg /etc/ansible/ansible.cfg

RUN  set -ex && \
  chmod 644  /etc/ansible/ansible.cfg && \
  chown devops /etc/ansible/ansible.cfg

COPY ./ansible /home/devops/ansible

# Clean up
RUN apt-get clean && \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin && \
    rm -rf /tmp/* /var/tmp/* && \
    rm /var/log/lastlog /var/log/faillog ;

USER devops

WORKDIR /home/devops/

#COPY env variable for govc ( vmware cli)
COPY ./docker/config/bash_aliases /home/devops/.bash_aliases

RUN  set -ex && \
  mkdir -p ~/requirements_ansible/roles \
    ~/requirements_ansible/modules\ 
    ~/requirements_ansible/modules_utils && \
  chmod  -R  775  ~/requirements_ansible

WORKDIR /tmp

RUN set -ex && \
  git clone https://github.com/stormshield/ansible-SNS && \
  mkdir  -p ~/requirements_ansible/modules/sns && \
  chmod  -R  775  ~/requirements_ansible/modules/sns  && \
  mv /tmp/ansible-SNS/library/* ~/requirements_ansible/modules/sns && \
  rm -rf /tmp/ansible-SNS

RUN set -ex && \
  git clone https://github.com/stormshield/sns-scripting && \
  mkdir  -p ~/requirements_ansible/roles/sns && \
  chmod  -R  775  ~/requirements_ansible/roles/sns  && \
  cp -r sns-scripting/ansible-roles/sns-* ~/requirements_ansible/roles/sns && \
  rm -rf /tmp/sns-scripting

WORKDIR /home/devops/

COPY ./docker/.requirements.yml /home/devops/ansible/.requirements.yml
RUN set -ex && \
  ansible-galaxy install --ignore-errors   -r /home/devops/ansible/.requirements.yml

COPY ./docker/bin/entrypoint.sh  /entrypoint.sh

ENTRYPOINT [ "/entrypoint.sh" ]