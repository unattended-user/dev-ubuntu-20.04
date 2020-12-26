FROM ubuntu:20.04 AS base
ARG TZ=UTC

## Install cURL, APT required tools and git
RUN DEBIAN_FRONTEND=noninteractive apt update && \
    DEBIAN_FRONTEND=noninteractive apt install --no-install-recommends --yes \
        curl \
        ca-certificates \
        apt-transport-https \
        gnupg-agent \
        software-properties-common \
        git \
    && \
    find /var/lib/apt/lists -maxdepth 1 -mindepth 1 -exec rm -r {} \;


FROM base AS golang
RUN DEBIAN_FRONTEND="noninteractive" apt update && \
    DEBIAN_FRONTEND="noninteractive" apt install --no-install-recommends --yes \
        golang \
        build-essential \
    && \
    find /var/lib/apt/lists -maxdepth 1 -mindepth 1 -exec rm -r {} \;

FROM golang AS ghcli
ARG GITHUB_TOKEN=0000000000000000000000000000000000000000
RUN mkdir -p /tmp/gh && \
    git clone --depth 1 https://${GITHUB_TOKEN}:x-oauth-basic@github.com/cli/cli.git /tmp/gh && \
    (cd /tmp/gh && make install) && \
    rm -R /tmp/gh

FROM base

## Docker Repo
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository --no-update "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
## Kubernetes repo
RUN curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - && \
    apt-add-repository --no-update "deb http://apt.kubernetes.io/ kubernetes-xenial main"
## Helm Repo
RUN curl -fsSL https://baltocdn.com/helm/signing.asc | apt-key add - && \
    apt-add-repository --no-update "deb https://baltocdn.com/helm/stable/debian/ all main"

## Install \
RUN DEBIAN_FRONTEND="noninteractive" apt update && \
    DEBIAN_FRONTEND="noninteractive" apt install --no-install-recommends --yes \
        sudo \
        bash-completion \
        tar \
        jq \
        docker-ce-cli \
        kubectl \
        helm \
        nano \
        openssh-client \
    && \
    find /var/lib/apt/lists -maxdepth 1 -mindepth 1 -exec rm -r {} \;

RUN curl --location --fail --output /usr/local/bin/skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64  && \
    chmod +x /usr/local/bin/skaffold

## Copy from other containers
COPY --from=ghcli /usr/local/bin/gh /usr/local/bin/gh

ARG GITHUB_TOKEN=0000000000000000000000000000000000000000

## Docker compose
RUN curl --location --fail --output /usr/local/bin/docker-compose $(gh api repos/docker/compose/releases/latest | jq -r .assets[].browser_download_url | grep -P "\/docker-compose-$(uname -s)-$(uname -m)$") && \
    chmod +x /usr/local/bin/docker-compose

## K9s
RUN curl --location --fail $(gh api repos/derailed/k9s/releases/latest | jq -r .assets[].browser_download_url | grep -P "/k9s_Linux_$(uname -m).tar.gz$") | tar -C /usr/local/bin -xvzf - k9s

## Auto completions
RUN kubectl completion bash > /etc/bash_completion.d/kubectl
RUN helm completion bash > /etc/bash_completion.d/helm
RUN skaffold completion bash > /etc/bash_completion.d/skaffold
RUN gh completion --shell bash > /etc/bash_completion.d/gh
RUN curl --location --fail --output /etc/bash_completion.d/docker-compose "https://raw.githubusercontent.com/docker/compose/$(docker-compose version | grep -P -o '^docker-compose version [0-9]+(\.[0-9]+)+' | grep -o -P '[0-9]+(\.[0-9]+)+$')/contrib/completion/bash/docker-compose"

## Setup user
ARG USER_ID=2000
ARG GROUP_ID=2000
ARG USER=${USER:-user}
ARG GROUP=${USER:-user}

RUN groupadd --gid "${GROUP_ID}" --force ${GROUP} && \
    useradd --system --create-home --home-dir "/home/${USER}" --shell /bin/bash --gid ${GROUP_ID} --groups sudo --uid "${USER_ID}" "${USER}" && \
    usermod -aG sudo "${USER}" && \
    echo "${USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

WORKDIR "/home/${USER}"
USER ${USER}