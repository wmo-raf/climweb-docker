FROM consbio/mbgl-renderer:0.8.0

RUN dpkgArch="$(dpkg --print-architecture)" && \
  DEBIAN_FRONTEND=noninteractive apt-get update && apt-get -y install \
  tini

ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "/root/entrypoint.sh" ]