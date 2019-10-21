# await.sh <a href="https://github.com/vegardit/await.sh/" title="GitHub Repo"><img height="30" src="https://raw.githubusercontent.com/simple-icons/simple-icons/develop/icons/github.svg?sanitize=true"></a>

[![Build Status](https://travis-ci.com/vegardit/await.sh.svg?branch=master)](https://travis-ci.com/vegardit/await.sh)
[![License](https://img.shields.io/github/license/vegardit/await.sh.svg?label=license)](#license)

1. [What is it?](#what-is-it)
1. [Usage](#usage)
    1. [await-cmd.sh](#await-cmd)
    1. [await-http.sh](#await-http)
    1. [await-tcp.sh](#await-tcp)
    1. [Docker Swarm Example](#swarm)
    1. [Kubernetes Example](#k8s)
1. [License](#license)


## <a name="what-is-it"></a>What is it?

This repository contains POSIX shell scripts that wait for a given time until resources (TCP ports, HTTP services) become available
and then execute predefined commands.

These scripts where created to workaround the fact that [Docker Swarm](https://docs.docker.com/engine/swarm/) does not support the
[depends_on](https://docs.docker.com/compose/compose-file/#depends_on) constraint of [Docker Compose](https://docs.docker.com/compose/),
which means there is no control over the startup order of multiple containers possible. For the interested reader, a lengthy discussion
about this issue can be found here https://github.com/moby/moby/issues/31333 with a lot of pros & cons.

In contrast to other third-party solutions, such as:
- https://github.com/betalo-sweden/await,
- https://github.com/Logimethods/docker-eureka, and
- https://github.com/vishnubob/wait-for-it (a fork of https://github.com/jlordiales/wait-for-it)

the scripts provided here have minimal system requirements (a POSIX shell, timeout, nc, wget), work with [BusyBox](https://busybox.net/),
[Alpine Linux](https://hub.docker.com/_/alpine) images and can be used without modifying existing images.

The scripts are automatically tested using [Bats](https://github.com/bats-core/) and executed under ash, bash, busybox, dash, ksh and zsh.


## <a name="usage"></a>Usage


### <a name="await-cmd"></a>await-cmd.sh

```sh
Usage: await-cmd.sh [OPTION]... TIMEOUT TEST_COMMAND [ARG...] [-- COMMAND [ARG...]]

Executes TEST_COMMAND repeatedly until it's exit code is 0. Then executes COMMAND.

Parameters:
  TIMEOUT       - Duration in seconds within TEST_COMMAND must return exit code 0.
  TEST_COMMAND  - Command that will be executed to test if the waiting condition is met.
  COMMAND       - Command to be executed once the TEST_COMMAND succeeded (optional).

Options:
  -f       - Force execution of COMMAND even if timeout occurred.
  -t SECS  - Duration in seconds after which a TEST_COMMAND process is terminated (optional, default: 10 seconds).
  -w SECS  - Waiting period in seconds between each execution of TEST_COMMAND (optional, default: 5 seconds).

Examples:
  await-cmd.sh 30 /opt/scripts/check_remote_services.sh -- /opt/server/start.sh --port 8080
  await-cmd.sh -w 10 30 /opt/scripts/check_remote_services.sh -- /opt/server/start.sh --port 8080
```


### <a name="await-http"></a>await-http.sh

```sh
Usage: await-http.sh [OPTION]... TIMEOUT URL... [-- COMMAND [ARG...]]

Repeatedly performs HTTP GET requests until the URL returns a HTTP status code <= 399. Then executes COMMAND.

Parameters:
  TIMEOUT  - Number of seconds within the URL must be reachable.
  URL      - URL(s) to be checked using HTTP GET.
  COMMAND  - Command to be executed once the wait condition is satisfied.

Options:
  -f       - Force execution of COMMAND even if timeout occurred.
  -t SECS  - Duration in seconds after which a connection attempt is aborted (optional, default: 10 seconds).
  -w SECS  - Duration in seconds to wait between retries (optional, default: 5 seconds).

Examples:
  await-http.sh 30 http://service1.local -- /opt/server/start.sh --port 8080
  await-http.sh 30 http://service1.local https://service2.local -- /opt/server/start.sh --port 8080
  await-http.sh -w 10 30 https://service1.local -- /opt/server/start.sh --port 8080
```


### <a name="await-tcp"></a>await-tcp.sh

```sh
Usage: await-tcp.sh [OPTION]... TIMEOUT HOSTNAME:PORT... [-- COMMAND [ARG...]]

Repeatedly attempts to connect to the given address until the TCP port is available. Then executes COMMAND.

Parameters:
  TIMEOUT        - Duration in seconds within the TCP port of the given host must be reachable.
  HOSTNAME:PORT  - Target TCP address(es) to connect to.
  COMMAND        - Command to be executed once a connection could be established (optional).

Options:
  -f       - Force execution of COMMAND even if timeout occurred.
  -t SECS  - Duration in seconds after which a connection attempt is aborted (optional, default: 10 seconds).
  -w SECS  - Duration in seconds to wait between retries (optional, default: 5 seconds).

Examples:
  await-tcp.sh 30 service1.local:389 -- /opt/server/start.sh --port 8080
  await-tcp.sh 30 service1.local:389 service2.local:5672 -- /opt/server/start.sh --port 8080
  await-tcp.sh -w 10 30 service1.local:389 -- /opt/server/start.sh --port 8080
```


### <a name="swarm"></a>Docker Swarm Example

Here is an example stack (compose file) where two nginx servers are started in an ordered fashion.

The idea is to upload the await script into the config store, then mount into a service
and override the default command. This way no additional Dockerfile/image needs to be created
containing the script to support horizontal scaling.

```yaml
version: '3.7'

configs:
  # stores the script into the swarm config service, which automatically distributes
  # it to the nodes running the containers.
  await_http_script:
    file: /opt/await/await-http.sh # existing path on the swarm master node

services:

  backend_service:
    image: karthequian/helloworld
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: on-failure
        delay: 5s

  frontend_service:
    image: karthequian/helloworld
    configs:
      # mount the script from config service into the container
      - source: await_http_script
        target: /await-http.sh
        mode: 0555
    command:
      # wait up to 30 seconds for backend_service to become available, then start nginx
      /await-http.sh 30 http://backend_service -- nginx
    ports:
      - 80:80
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: on-failure
        delay: 5s
```


### <a name="k8s"></a>Kubernetes Example

TODO Mount config files

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp-deployment
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: deployment
    spec:
      containers:
      - name: backend_service
        image: karthequian/helloworld
        imagePullPolicy: Always
        ports:
        - containerPort: 80
        readinessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 10
      - name: frontend_service
        image: karthequian/helloworld
        imagePullPolicy: Always
        args:
          # wait up to 30 seconds for backend_service to become available, then start nginx
          /await-http.sh 30 http://backend_service -- nginx
        ports:
        - containerPort: 80
        readinessProbe:
          tcpSocket:
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 10
```


## <a name="license"></a>License

All files are released under the [Apache License 2.0](LICENSE.txt).