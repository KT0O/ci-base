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
  curl -L -o sbt-$SBT_VERSION.deb https://dl.bintray.com/sbt/debian/sbt-$SBT_VERSION.deb && \
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

# installing docker from underlying distro, for DinD
RUN apt-get install -y docker.io socat certbot cron jq && \
  rm -rf /var/lib/apt/lists/*

# installing acme.sh
RUN curl https://get.acme.sh | sh && \
  cp /root/.acme.sh/acme.sh /usr/local/bin/ && \
  /root/.acme.sh/acme.sh --uninstall && \
  rm -rf /root/.acme.sh

# installing sscep
RUN apt-get update && \
  apt-get install -y git make gcc libssl-dev && \
  git clone https://github.com/certnanny/sscep.git && \
  ln -s /usr/lib/x86_64-linux-gnu openssl && \
  cd /root/sscep && \
  ./Configure && \
  make && \
  cp /root/sscep/sscep_static /usr/local/bin/sscep && \
  cd /root && \
  rm -f openssl && \
  rm -rf sscep && \
  apt-get remove -y gcc libssl-dev libc6-dev gcc-8 linux-libc-dev cpp cpp-8 libgcc-8-dev libc-dev-bin && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

WORKDIR /root
