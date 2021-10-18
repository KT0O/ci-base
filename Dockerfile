# Using Scala-sbt base image

# Pull base image
ARG BASE_IMAGE_TAG
FROM openjdk:${BASE_IMAGE_TAG:-8u252-jdk-buster}

# Env variables
ARG SCALA_VERSION
ENV SCALA_VERSION ${SCALA_VERSION:-2.13.3}
ARG SBT_VERSION
ENV SBT_VERSION ${SBT_VERSION:-1.3.12}
ARG USER_ID
ENV USER_ID ${USER_ID:-1001}
ARG GROUP_ID 
ENV GROUP_ID ${GROUP_ID:-1001}

# Install sbt
RUN \
  curl -L -o sbt-$SBT_VERSION.deb https://repo.scala-sbt.org/scalasbt/debian/sbt-$SBT_VERSION.deb && \
  dpkg -i sbt-$SBT_VERSION.deb && \
  rm sbt-$SBT_VERSION.deb && \
  apt-get update && \
  apt-get install sbt

# Install Scala
## Piping curl directly in tar
RUN \
  curl -fsL https://downloads.typesafe.com/scala/$SCALA_VERSION/scala-$SCALA_VERSION.tgz | tar xfz - -C /usr/share && \
  mv /usr/share/scala-$SCALA_VERSION /usr/share/scala && \
  chown -R root:root /usr/share/scala && \
  chmod -R 755 /usr/share/scala && \
  ln -s /usr/share/scala/bin/scala /usr/local/bin/scala

# Add and use user sbtuser
RUN groupadd --gid $GROUP_ID sbtuser && useradd --gid $GROUP_ID --uid $USER_ID sbtuser --shell /bin/bash && \
  chown -R sbtuser:sbtuser /opt && \
  mkdir /home/sbtuser && chown -R sbtuser:sbtuser /home/sbtuser && \
  mkdir /logs && chown -R sbtuser:sbtuser /logs
  
USER sbtuser

# Switch working directory
WORKDIR /home/sbtuser

# Prepare sbt (warm cache)
RUN \
  sbt sbtVersion && \
  mkdir -p project && \
  echo "scalaVersion := \"${SCALA_VERSION}\"" > build.sbt && \
  echo "sbt.version=${SBT_VERSION}" > project/build.properties && \
  echo "case object Temp" > Temp.scala && \
  sbt compile && \
  rm -rf project && rm -f build.sbt && rm -f Temp.scala && rm -rf target

# Link everything into root as well
# This allows users of this container to choose, whether they want to run the container as sbtuser (non-root) or as root
USER root
RUN \
  ln -s /home/sbtuser/.cache /root/.cache && \
  ln -s /home/sbtuser/.ivy2 /root/.ivy2 && \
  ln -s /home/sbtuser/.sbt /root/.sbt

# Switch working directory back to root
## Users wanting to use this container as non-root should combine the two following arguments
## -u sbtuser
## -w /home/sbtuser
WORKDIR /root    

# installing the rest
RUN apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common socat certbot cron jq rpm python3 python3-pip aspell aspell-en aspell-fr && \
  pip3 install pyspelling && \
  rm -rf /var/lib/apt/lists/*

# installing docker client
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian buster stable" && \
  apt update && \
  apt install -y docker-ce

# installing acme.sh
RUN curl https://get.acme.sh | sh && \
  cp /root/.acme.sh/acme.sh /usr/local/bin/ && \
  /root/.acme.sh/acme.sh --uninstall && \
  rm -rf /root/.acme.sh

# installing lego
RUN curl -L -o lego.tgz https://github.com/go-acme/lego/releases/download/v3.9.0/lego_v3.9.0_linux_amd64.tar.gz && \
  tar xzf lego.tgz && \
  mv lego /usr/local/bin/ && \
  rm -f lego.tgz CHANGELOG.md LICENSE

# installing sscep
RUN apt-get update && \
  apt-get install -y git make gcc libssl-dev && \
  git clone https://github.com/certnanny/sscep.git && \
  ln -s /usr/lib/x86_64-linux-gnu openssl && \
  cd /root/sscep && \
  git fetch --all --tags && \
  git checkout tags/v0.7.0 -b v0.7.0-branch && \
  ./Configure && \
  make && \
  cp /root/sscep/sscep_static /usr/local/bin/sscep && \
  cd /root && \
  rm -f openssl && \
  rm -rf sscep && \
  apt-get remove -y gcc libssl-dev libc6-dev gcc-8 linux-libc-dev cpp cpp-8 libgcc-8-dev libc-dev-bin && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# installing libest
RUN apt-get update && \
  apt-get install -y git make gcc libssl-dev liburiparser-dev && \
  cd /root && \
  curl -L -o libest.tar.gz https://github.com/cisco/libest/archive/r3.2.0.tar.gz && \
  tar xzf libest.tar.gz && \
  cd /root/libest-r3.2.0 && \
  ./configure --enable-client-only --with-uriparser-dir=/usr/include/uriparser; make ; make install && \
  cd /root && \
  rm -rf /root/libest-r3.2.0 && \
  apt-get remove -y gcc libssl-dev libc6-dev gcc-8 linux-libc-dev cpp cpp-8 libgcc-8-dev libc-dev-bin liburiparser-dev && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# installing newman
RUN apt-get update && \
  apt-get install -y npm && \
  npm install -g newman && \
  npm install -g newman-reporter-junitfull && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# installing mongodb
RUN wget -qO - https://www.mongodb.org/static/pgp/server-4.2.asc | apt-key add -&& \
  echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/4.2 main" | tee /etc/apt/sources.list.d/mongodb-org-4.2.list && \
  apt-get update && \
  apt-get install -y mongodb-org-shell && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# installing QA Root CA
RUN echo -e "-----BEGIN CERTIFICATE-----\nMIIFeDCCA2CgAwIBAgIITDM8XNhFcKUwDQYJKoZIhvcNAQELBQAwQDELMAkGA1UE\nBhMCRlIxEjAQBgNVBAoTCUV2ZXJUcnVzdDEdMBsGA1UEAxMURXZlclRydXN0IFFB\nIFJvb3QgQ0EwHhcNMjAwMjE4MDAwMDAwWhcNNDAwMjE3MjM1OTU5WjBAMQswCQYD\nVQQGEwJGUjESMBAGA1UEChMJRXZlclRydXN0MR0wGwYDVQQDExRFdmVyVHJ1c3Qg\nUUEgUm9vdCBDQTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALtvfXMN\nXBTcRjUJkDxclZayys1hjXLi5596Xw28/NknlCyU0Xn4tZJdmAwYexWwAxEZkuFn\nTDnxVTgDzQ4eoEuQAHjYAdkJe8J4AB+NknA8cZsyp8bSf9QbEFYIZKToxtB19VVL\nPetylyfL6iePaGzC1BW4BA8+Ol8Iu6CUA1xOXJL4sFfdbFhPQ7QzlhSebRJoPqY2\nry4ESIvq2N5TusBPS/GC5jfroF4Xc0IAvtKOOWFJXtj/eI4bs/vNdW8OKA3ev1BR\nlfbUiDkpj3qtMptjn+MNqdbB8+iIskf1UYzS4Aiva+8r7QcuppeyZE+9KPMQhjOM\nwdV9GFEW3rEXfcbY/kIs3vlEuN8UhQGa87/vyv900bVjKgekRI9zNID6GRMkiVg5\nGu9hCKFrFDxoo7AtYYnrneHlHRMj/lWGW3GSZ6p8gN9pb7TZtK3+QTA+urzpw19Q\ncKNLPbwYUz4IAQDiFedem8iIX+ZZ7Mg17RZ82RrMMjF/f56QzY2X90ojm1aItUIb\nD6xUxRo7CuiCYxNhovyG6jxGCj+IpM07SSDpUSL+G0rUm7EDL4W9CqVKnOgl7N5H\nfflrgveXqCYEsdILz5wVeYKIUjWWY+BMNJvcJogYuzhcUqbbGOWBUvKqut+A8vwl\nNhxHYpVgNX0Cg4ooPI0WIROKWFGyDlsfrMBVAgMBAAGjdjB0MA8GA1UdEwEB/wQF\nMAMBAf8wHQYDVR0OBBYEFLXJ6OUfgI1+XhNPGTrA2GHhxYM8MB8GA1UdIwQYMBaA\nFLXJ6OUfgI1+XhNPGTrA2GHhxYM8MA4GA1UdDwEB/wQEAwIBBjARBgNVHSAECjAI\nMAYGBFUdIAAwDQYJKoZIhvcNAQELBQADggIBADOFDMCbmozRg7qJh9uxqIB4jMZ9\nFNYDa2r9h+dVrNSn7YRlnNpP/gnSCuzgCRZ/IJLmVWyEkpklrwMiDNnV6cpUv5LO\nZfkbTNDW6BIptnq9Re4J6wKcO8LsCn5HLGV6VQkboSHA+mnu2inUv8VT7R36A3+O\nv7zna/Zl/aNBwrM59yIRABt5L+Vu9OLgTRK14sxtEnFtmStZfNFLzPx08Z+Y2C4k\n5yG1sri7s2O/gVoSqMCVHJxRn1HEsRZlc9SrT+n6x7MvRvmEZr5bOxkZx2GxfxBP\nNqESv5pWiZew6qqTDbgTDteusRv/5vcc62paqJFB/YkKNdw6f7/mO1l5XmuyfR46\ngu6CZIfTuX0SK5v2k5Tx+/aR4SVbVZ2J9CnqNcU4u7QDurTPLERYxvYfIw7BjmWV\nTyQvX/gQDAoeW4NaKaZKfY69ac+tI/AciEQfvr208XG2n26aySGpQ4DePreV4Qkf\naEXVILU0+Qme7lJX8rV1yIRbBnWoP5yErh2bJaYbyDviVvyBPKUC+3rpAapYPSvA\nPZXcttOjBtv96S1YBtbQ/vK7A9JjxAuKJuqKiqm6mg02Go7tDJzmqtulXFOdzkcx\nqVnHLm+4oDYznBZ5NchnHdh4YNdrMet3U93zfGP4W7kkLzZeLYdH++YD31B4r1UU\nqrrB4gD9c7/yxotg\n-----END CERTIFICATE-----" > /usr/local/share/ca-certificates/qarca.crt && \
  update-ca-certificates

WORKDIR /root
