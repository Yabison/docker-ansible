###############################################################################
# var definition
###############################################################################
PATH_ROOT = $(shell pwd)
DOCKER_COMPOSE = docker-compose
DOCKER_COMPOSE_FILE = docker-compose.yml


###############################################################################
# Available list (containers, actions, ...)
###############################################################################
CONTAINERS = ansible 
ACTIONS = build up start restart run stop halt logs bash

###############################################################################
# Set production environment (default)
###############################################################################
DOCKER_COMPOSE_FILE_SELECTED = $(DOCKER_COMPOSE_FILE)
ENVIRONMENT_FILE = $(PATH_ROOT)/.docker.env

###############################################################################
# Set environment (dev or prod)
###############################################################################
ENVIRONMENT = $(shell [ -f ../ENV ] && cat ../ENV || echo production)
$(info $$ENVIRONMENT is [${ENVIRONMENT}])

###############################################################################
# Override environment (if necessary)
###############################################################################
ifeq ($(ENVIRONMENT), development)
DOCKER_COMPOSE_FILE_SELECTED = $(DOCKER_COMPOSE_FILE) -f $(DOCKER_COMPOSE_DEV_FILE)
ENVIRONMENT_FILE = $(PATH_ROOT)/config/.docker-dev.env
endif

###############################################################################
# targets to manage all containers
###############################################################################
# build-project ==> Build the project
#build-project: pre-build-containers build-containers upall
build-project: build-containers upall

# buildall ===> build all containers
#buildall : prerequisite pre-build-containers build-containers
buildall : prerequisite  build-containers

# downall ===> down all containers
downall : prerequisite
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) down

# upall ===> up all containers
upall : prerequisite 
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) up -d

# haltall ===> Halts all the docker containers
haltall: prerequisite  valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) kill

###############################################################################
# target to clean docker images and dependencies
###############################################################################
# clean ===> remove the docker containers and deletes project dependencies
clean: prerequisite prompt-continue
	# Remove the docker containers
	$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_BUILD_FILE) down --rmi all -v --remove-orphans
	$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) down --rmi all -v --remove-orphans

###############################################################################
# targets to manage individual container
###############################################################################
# build ===> compile given container
build: prerequisite valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) build --no-cache $(filter-out $@,$(MAKECMDGOALS))

# up ===> Builds, (re)creates, starts, and attaches to containers for a service.
up: prerequisite valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) up -d  $(filter-out $@,$(MAKECMDGOALS))

# restart ===> stop container and start container
restart:
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) stop $(filter-out $@,$(MAKECMDGOALS))
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) start $(filter-out $@,$(MAKECMDGOALS))

# start ===> Starts existing containers for a service (make start <container>)
start: prerequisite valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) start $(filter-out $@,$(MAKECMDGOALS))
	
# run ===> run nprogram in given container
run: prerequisite valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) run --rm $(filter-out $@,$(MAKECMDGOALS))

# stop ===> Stop existing containers for a service.
stop: prerequisite valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) stop $(filter-out $@,$(MAKECMDGOALS))

# halt ===> Halts the docker containers
halt: prerequisite  valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) kill $(filter-out $@,$(MAKECMDGOALS))

# Logs ==> get logs from the docker containers
logs: prerequisite valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) logs --tail=100 -f $(filter-out $@,$(MAKECMDGOALS))

###############################################################################
# status container(s)
###############################################################################
# status ===> Echos the container status
status: prerequisite
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) ps

# config ===> get container gonfig
config: prerequisite
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) config

###############################################################################
# connect container(s)
###############################################################################
# bash ===> get bash into the docker containers
bash: prerequisite valid-container selectcomposefile
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) exec $(filter-out $@,$(MAKECMDGOALS)) bash


###############################################################################
# internal targets prerequisite
###############################################################################
prerequisite:
# $(info prerequisite call)
include $(ENVIRONMENT_FILE)
export ENV_FILE = $(ENVIRONMENT_FILE)
export PROJECT_DIRECTORY = $(PATH_ROOT)

###############################################################################
# internal target valid-container
###############################################################################
valid-container:
# $(info valid-container call)
ifeq ($(filter-out $(ACTIONS) $@,$(MAKECMDGOALS)),)
	$(error empty container to build)
endif
ifeq ($(filter $(filter-out $(ACTIONS) $@,$(MAKECMDGOALS)),$(CONTAINERS)),)
	$(error Invalid container provided "$(filter-out $(ACTIONS) $@,$(MAKECMDGOALS))")
endif

###############################################################################
# internal target pre-build-containers
###############################################################################
pre-build-containers:
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_BUILD_FILE) build

###############################################################################
# internal target build-containers
###############################################################################
build-containers:
	@$(DOCKER_COMPOSE) --env-file $(ENV_FILE) -f $(DOCKER_COMPOSE_FILE_SELECTED) up -d --build


###############################################################################
# internal target prompt
###############################################################################
# prompt-continue ===> Prompt to continue
prompt-continue:
	@while [ -z "$$CONTINUE" ]; do \
		read -r -p "Would you like to continue? [y]" CONTINUE; \
	done ; \
	if [ ! $$CONTINUE == "y" ]; then \
        echo "Exiting." ; \
        exit 1 ; \
    fi

%:
	@: