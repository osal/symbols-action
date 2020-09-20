# Container image that runs your code
FROM debian:10.4

# install necessary tools (wget, unzip, git, jq, GitHub CLI, AWS CLI)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git wget zip unzip jq && \
    wget -nv https://github.com/cli/cli/releases/download/v0.10.1/gh_0.10.1_linux_amd64.deb && \
    apt-get install -y ./gh_*_linux_amd64.deb && \
    wget -nv "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -O "awscliv2.zip" && \
    unzip -q awscliv2.zip && \
    ./aws/install && \
    rm ./awscliv2.zip && \
    rm -r ./aws && \
    rm ./gh_*_linux_amd64.deb && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copies your code file from your action repository to the filesystem path `/` of the container
COPY entrypoint.sh /entrypoint.sh

# Code file to execute when the docker container starts up (`entrypoint.sh`)
ENTRYPOINT ["/entrypoint.sh"]
