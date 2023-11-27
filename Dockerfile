# Using Scala-sbt base image

# Pull base image
ARG BASE_IMAGE_TAG
FROM eclipse-temurin:${BASE_IMAGE_TAG:-8u252-jdk-buster}

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
RUN apt-get install -y apt-transport-https xxd ca-certificates curl gnupg2 software-properties-common socat certbot cron jq rpm nginx python3 python3-pip aspell aspell-en aspell-fr qemu-user softhsm2 && \
  pip3 install pyspelling && \
  pip3 install lemoncheesecake[junit] && \
  pip3 install lemoncheesecake-requests && \
  rm -rf /var/lib/apt/lists/*

# installing docker client
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian buster stable" && \
  apt update && \
  apt install -y docker-ce docker-ce-cli containerd.io

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
  apt-get install -y git make gcc libssl-dev pkg-config libtool automake autoconf && \
  git clone https://github.com/certnanny/sscep.git && \
  cd /root/sscep && \
  git fetch --all --tags && \
  git checkout tags/v0.10.0 -b v0.10.0-branch && \
  ./bootstrap.sh && \
  ./configure && \
  make && \
  make install && \
  rm -rf sscep && \
  apt-get remove -y gcc libssl-dev libc6-dev gcc-10 linux-libc-dev cpp cpp-10 libgcc-10-dev libc-dev-bin pkg-config libtool automake autoconf && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# installing libest
RUN apt-get update && \
  apt-get install -y git make gcc libssl-dev liburiparser-dev && \
  cd /root && \
  curl -L -o libest.tar.gz https://github.com/cisco/libest/archive/r3.2.0.tar.gz && \
  tar xzf libest.tar.gz && \
  cd /root/libest-r3.2.0 && \
  perl -pi -e "s/int e_ctx_ssl_exdata_index/\/\/int e_ctx_ssl_exdata_index/" src/est/est_locl.h && \
  ./configure --enable-client-only --with-uriparser-dir=/usr/include/uriparser; make ; make install && \
  cd /root && \
  rm -rf /root/libest-r3.2.0 && \
  apt-get remove -y gcc libssl-dev libc6-dev gcc-10 linux-libc-dev cpp cpp-10 libgcc-10-dev libc-dev-bin liburiparser-dev && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# installing newman
RUN mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  apt-get install -y nodejs npm && \
  npm install -g newman@5.3.2 newman-reporter-junitfull newman-reporter-htmlextra && \
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
RUN echo "3082057830820360a00302010202084c333c5cd84570a5300d06092a864886f70d01010b05003040310b300906035504061302465231123010060355040a1309457665725472757374311d301b0603550403131445766572547275737420514120526f6f74204341301e170d3230303231383030303030305a170d3430303231373233353935395a3040310b300906035504061302465231123010060355040a1309457665725472757374311d301b0603550403131445766572547275737420514120526f6f7420434130820222300d06092a864886f70d01010105000382020f003082020a0282020100bb6f7d730d5c14dc463509903c5c9596b2cacd618d72e2e79f7a5f0dbcfcd927942c94d179f8b5925d980c187b15b003111992e1674c39f1553803cd0e1ea04b900078d801d9097bc278001f8d92703c719b32a7c6d27fd41b10560864a4e8c6d075f5554b3deb729727cbea278f686cc2d415b8040f3e3a5f08bba094035c4e5c92f8b057dd6c584f43b43396149e6d12683ea636af2e04488bead8de53bac04f4bf182e637eba05e17734200bed28e3961495ed8ff788e1bb3fbcd756f0e280ddebf505195f6d48839298f7aad329b639fe30da9d6c1f3e888b247f5518cd2e008af6bef2bed072ea697b2644fbd28f31086338cc1d57d185116deb1177dc6d8fe422cdef944b8df1485019af3bfefcaff74d1b5632a07a4448f733480fa1913248958391aef6108a16b143c68a3b02d6189eb9de1e51d1323fe55865b719267aa7c80df696fb4d9b4adfe41303ebabce9c35f5070a34b3dbc18533e080100e215e75e9bc8885fe659ecc835ed167cd91acc32317f7f9e90cd8d97f74a239b5688b5421b0fac54c51a3b0ae882631361a2fc86ea3c460a3f88a4cd3b4920e95122fe1b4ad49bb1032f85bd0aa54a9ce825ecde477df96b82f797a82604b1d20bcf9c1579828852359663e04c349bdc268818bb385c52a6db18e58152f2aabadf80f2fc25361c47629560357d02838a283c8d1621138a5851b20e5b1facc0550203010001a3763074300f0603551d130101ff040530030101ff301d0603551d0e04160414b5c9e8e51f808d7e5e134f193ac0d861e1c5833c301f0603551d23041830168014b5c9e8e51f808d7e5e134f193ac0d861e1c5833c300e0603551d0f0101ff04040302010630110603551d20040a300830060604551d2000300d06092a864886f70d01010b0500038202010033850cc09b9a8cd183ba8987dbb1a880788cc67d14d6036b6afd87e755acd4a7ed84659cda4ffe09d20aece009167f2092e6556c84929925af03220cd9d5e9ca54bf92ce65f91b4cd0d6e81229b67abd45ee09eb029c3bc2ec0a7e472c657a55091ba121c0fa69eeda29d4bfc553ed1dfa037f8ebfbce76bf665fda341c2b339f72211001b792fe56ef4e2e04d12b5e2cc6d12716d992b597cd14bccfc74f19f98d82e24e721b5b2b8bbb363bf815a12a8c0951c9c519f51c4b1166573d4ab4fe9fac7b32f46f98466be5b3b1919c761b17f104f36a112bf9a568997b0eaaa930db8130ed7aeb11bffe6f71ceb6a5aa89141fd890a35dc3a7fbfe63b59795e6bb27d1e3a82ee826487d3b97d122b9bf69394f1fbf691e1255b559d89f429ea35c538bbb403bab4cf2c4458c6f61f230ec18e65954f242f5ff8100c0a1e5b835a29a64a7d8ebd69cfad23f01c88441fbebdb4f171b69f6e9ac921a94380de3eb795e1091f6845d520b534f9099eee5257f2b575c8845b0675a83f9c84ae1d9b25a61bc83be256fc813ca502fb7ae901aa583d2bc03d95dcb6d3a306dbfde92d5806d6d0fef2bb03d263c40b8a26ea8a8aa9ba9a0d361a8eed0c9ce6aadba55c539dce4731a959c72e6fb8a036339c167935c8671dd87860d76b31eb7753ddf37c63f85bb9242f365e2d8747fbe603df5078af5514aabac1e200fd73bff2c68b60" | xxd -r -p | openssl x509 -inform DER> /usr/local/share/ca-certificates/qa-rca.crt && \
  cat /usr/local/share/ca-certificates/qa-rca.crt && \
  echo "3082060c308203f4a003020102020810a2e1617dee1bd8300d06092a864886f70d01010b050030818b310b3009060355040613024652310e300c060355040813055061726973310e300c06035504071305506172697331123010060355040a1309457665725472757374310b3009060355040b13025244311a30180603550403131145766572547275737420526f6f74204341311f301d06092a864886f70d0109011610726e64406576657274727573742e6672301e170d3233303231353135313230305a170d3338303231353135313230305a30818b310b3009060355040613024652310e300c060355040813055061726973310e300c06035504071305506172697331123010060355040a1309457665725472757374310b3009060355040b13025244311a30180603550403131145766572547275737420526f6f74204341311f301d06092a864886f70d0109011610726e64406576657274727573742e667230820222300d06092a864886f70d01010105000382020f003082020a0282020100b89a4ec8c794dcfeadd31fe36dcc19d039d1f7b97f2da5b2099989578a8c42b668be1ac0afd7c309f9e6dc50dba5e6e956dd14638164469381856d4fde10d3ae4f1e48e3cd20f2bee05671787f40584171c5c1add199309cb04919e27ed98cff0ee21157eb7e7475fc2ae406f18b0e7f254d3081fef8d92dd37fc8f185a18644433a4f58e49f6aee6d237659578798a95c0f8b8ed0836224049b5e63d2a4ada02973430b22cc1176de30101d0364a61aa98ca9724a8241f0fed13e68cafdc23f6bf054615c20d330ced7abfc655ab9aeb89245129dadcf28970ffeb448aa699f5f194255a851c2a17dedd8219ad33c42c9f1d85f904f108a6f9735df3223d35559d5607d90c1187aa550c38f632f95b83dbaca6ec6e6422fb17c7466757f3f9ce1344cf6c2851983d0520ff958ca3f74c0fc7e3566c268eec7530fcb3e200577f9ce2916634c7ce1d579133fe394f239aee9db9603776285f4930be2122f81c3ac57210b53019d71b8b17025cf04c130a39af11bc662cdcc8ad4fc9354b7637eaf67ff3576d752ba9b628ac8a535e86376e931298616c86e8674a8e01e9de0438ebc8ffc156f43bddfe3c950617ce4202789957a93acd951e7011fb472f8066496ca1563976ba77c259988ecad2760f30f85198dea540cda7ff4564778782b5cba456e6ed87310e1453d9e0ede3097ad8d1015d8b3a295847a02505ff8bc8b350203010001a3723070300f0603551d130101ff040530030101ff301d0603551d0e04160414dd3598c3fbf7661d666732516e8ebbaa60b8dbe1300b0603551d0f040403020106301106096086480186f8420101040403020007301e06096086480186f842010d0411160f786361206365727469666963617465300d06092a864886f70d01010b05000382020100009946347ab97d3c608ec6da51472a55f8afd62fff781cfb4a988024994f7cef78b278208afd635bb686e0d5119c0988889de92f30abfc53b808f7d3772a2965773be4d8c1d4879831761a49b24039c3602f8448b1519e8796982386ec447fb5c4f84a2b77b953145966de3a491f535970120d0466b8efe7923cc6845b91bec563ce54b2d771f80065c2bf96767535861f6b3beb4cf6102ebc0eb76a5c6439526b2cf6aa42fefc53b0fe404b0372ed5fbfaa6adea56387231283cef010f6041fb1cff283cfa760645d29573eff0c3bbd64afafcd09c2bbcfcda7a254d6c709a3d7112e003714c5565c6ec1364247917d28b9b08d5b3f35ba91de73279e991ad63d43e72636a1bc27d2b1dbb2d41411c1be6c421a28e75ada27c2297c45cfc8d22d9bc3a422f2442552ad9c81dd717c96a2a2411ebe03b244e95c2a88695321cdf8a9ee02434457c4799bd20a0b90f91afd449f84bc84feb4ee100e647fb7b81c22644ecd98cf9c467de891338e0175d48db3e43fb2cd7a7dc425dd0c709604138175eb1d5711d0d41c686fffc27c4d355dc34eb5bd720b0b7f71f03c91e55a3ddbeb2d9d33b9347f89622295d0fc40733b3f3829c46f07379b1c90700026c2be443594d61c15f732d11e5ad473928ff62b4d730f450d4d037515b75db2a3ceb7fb2f3509461cb3d8e565ae0cdf19cb898190d804af497ca6d0c4858591396f9b" | xxd -r -p | openssl x509 -inform DER> /usr/local/share/ca-certificates/evt-rca.crt && \
  cat /usr/local/share/ca-certificates/evt-rca.crt && \
  update-ca-certificates && \
  keytool -import -trustcacerts -cacerts -storepass changeit -noprompt -alias evt-rca -file /usr/local/share/ca-certificates/evt-rca.crt

WORKDIR /root
