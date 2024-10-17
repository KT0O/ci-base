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

# installing the rest and lcc
RUN apt-get install -y apt-transport-https xxd ca-certificates curl gnupg2 software-properties-common socat certbot cron jq rpm nginx python3 python3-pip aspell aspell-en aspell-fr qemu-user softhsm2 libxml2-dev libxslt1-dev clamav && \
  pip3 install pyspelling && \
  pip3 install lemoncheesecake[junit] && \
  pip3 install lemoncheesecake-requests && \
  freshclam && \
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
  
# installing bru
RUN mkdir -p /etc/apt/keyrings && \
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
  apt-get update && \
  apt-get install -y nodejs && \
  npm install -g @usebruno/cli@1.33.0 && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# modifying the bru CLI to fix https://github.com/usebruno/bruno/issues/3311
RUN perl -pi -e "s/2\)/2\).replaceAll\('\\$','\\$\\$\\$\\$'\)/g" /usr/lib/node_modules/@usebruno/cli/src/reporters/html.js
  
# installing mongodb
RUN wget -qO - https://www.mongodb.org/static/pgp/server-5.0.asc | apt-key add -&& \
  echo "deb http://repo.mongodb.org/apt/debian buster/mongodb-org/5.0 main" | tee /etc/apt/sources.list.d/mongodb-org-5.0.list && \
  apt-get update && \
  apt-get install -y mongodb-org-shell && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
  
# installing QA Root CA
RUN echo "3082057830820360a00302010202084c333c5cd84570a5300d06092a864886f70d01010b05003040310b300906035504061302465231123010060355040a1309457665725472757374311d301b0603550403131445766572547275737420514120526f6f74204341301e170d3230303231383030303030305a170d3430303231373233353935395a3040310b300906035504061302465231123010060355040a1309457665725472757374311d301b0603550403131445766572547275737420514120526f6f7420434130820222300d06092a864886f70d01010105000382020f003082020a0282020100bb6f7d730d5c14dc463509903c5c9596b2cacd618d72e2e79f7a5f0dbcfcd927942c94d179f8b5925d980c187b15b003111992e1674c39f1553803cd0e1ea04b900078d801d9097bc278001f8d92703c719b32a7c6d27fd41b10560864a4e8c6d075f5554b3deb729727cbea278f686cc2d415b8040f3e3a5f08bba094035c4e5c92f8b057dd6c584f43b43396149e6d12683ea636af2e04488bead8de53bac04f4bf182e637eba05e17734200bed28e3961495ed8ff788e1bb3fbcd756f0e280ddebf505195f6d48839298f7aad329b639fe30da9d6c1f3e888b247f5518cd2e008af6bef2bed072ea697b2644fbd28f31086338cc1d57d185116deb1177dc6d8fe422cdef944b8df1485019af3bfefcaff74d1b5632a07a4448f733480fa1913248958391aef6108a16b143c68a3b02d6189eb9de1e51d1323fe55865b719267aa7c80df696fb4d9b4adfe41303ebabce9c35f5070a34b3dbc18533e080100e215e75e9bc8885fe659ecc835ed167cd91acc32317f7f9e90cd8d97f74a239b5688b5421b0fac54c51a3b0ae882631361a2fc86ea3c460a3f88a4cd3b4920e95122fe1b4ad49bb1032f85bd0aa54a9ce825ecde477df96b82f797a82604b1d20bcf9c1579828852359663e04c349bdc268818bb385c52a6db18e58152f2aabadf80f2fc25361c47629560357d02838a283c8d1621138a5851b20e5b1facc0550203010001a3763074300f0603551d130101ff040530030101ff301d0603551d0e04160414b5c9e8e51f808d7e5e134f193ac0d861e1c5833c301f0603551d23041830168014b5c9e8e51f808d7e5e134f193ac0d861e1c5833c300e0603551d0f0101ff04040302010630110603551d20040a300830060604551d2000300d06092a864886f70d01010b0500038202010033850cc09b9a8cd183ba8987dbb1a880788cc67d14d6036b6afd87e755acd4a7ed84659cda4ffe09d20aece009167f2092e6556c84929925af03220cd9d5e9ca54bf92ce65f91b4cd0d6e81229b67abd45ee09eb029c3bc2ec0a7e472c657a55091ba121c0fa69eeda29d4bfc553ed1dfa037f8ebfbce76bf665fda341c2b339f72211001b792fe56ef4e2e04d12b5e2cc6d12716d992b597cd14bccfc74f19f98d82e24e721b5b2b8bbb363bf815a12a8c0951c9c519f51c4b1166573d4ab4fe9fac7b32f46f98466be5b3b1919c761b17f104f36a112bf9a568997b0eaaa930db8130ed7aeb11bffe6f71ceb6a5aa89141fd890a35dc3a7fbfe63b59795e6bb27d1e3a82ee826487d3b97d122b9bf69394f1fbf691e1255b559d89f429ea35c538bbb403bab4cf2c4458c6f61f230ec18e65954f242f5ff8100c0a1e5b835a29a64a7d8ebd69cfad23f01c88441fbebdb4f171b69f6e9ac921a94380de3eb795e1091f6845d520b534f9099eee5257f2b575c8845b0675a83f9c84ae1d9b25a61bc83be256fc813ca502fb7ae901aa583d2bc03d95dcb6d3a306dbfde92d5806d6d0fef2bb03d263c40b8a26ea8a8aa9ba9a0d361a8eed0c9ce6aadba55c539dce4731a959c72e6fb8a036339c167935c8671dd87860d76b31eb7753ddf37c63f85bb9242f365e2d8747fbe603df5078af5514aabac1e200fd73bff2c68b60" | xxd -r -p | openssl x509 -inform DER> /usr/local/share/ca-certificates/qa-rca.crt && \
  cat /usr/local/share/ca-certificates/qa-rca.crt && \
  echo "3082059130820379a00302010202083410b6e35eeab3ab300d06092a864886f70d01010b05003056310b300906035504061302465231123010060355040a130945564552545255535431173015060355040b130e3030303220383239363032353938311a30180603550403131145564552545255535420526f6f74204341301e170d3234303133313030303030305a170d3434303133303233353935395a3056310b300906035504061302465231123010060355040a130945564552545255535431173015060355040b130e3030303220383239363032353938311a30180603550403131145564552545255535420526f6f7420434130820222300d06092a864886f70d01010105000382020f003082020a0282020100ab63af2fecd6031006b1a807a239ee09ff37fd4300eddfd0b2fdf5cba2677ee8216ccda1f5749b26a4bdf2b0421e2a3d41e82b516d5a33ba05bc22d2d28a0b8aead9e306b26ab892fc524c00dc22b9d4d83e9de282fe7b4c570827ec209b86f4920a46dbd449fec5950e0c2373a9806a37c4d53b0886467f910e98631f82d3026916c2010e50eebffb19609949c213a4213e7622753208b96db4aa99cee002edcb6bccfe3e541239bb5d74790e03fc7a48350341424f200f6bd1e84996cf1a118f124930987504e2965af0a1904362e337a815e3ddf2d9920802f2be0c4b2b45f31bd66fa191ccb66e59b06374577e21916624acd97af6ce6407af9db7afe4c51e6a099f097843cfde655a3732adb2bdb1bf401df60dfeda44afacf6337379b13dbc84f4fc14c8b0769cbb06c2b864351e4b04fc8912afa89dfa5108616e837cefe9a75e94cf8d5a7a6a34215bb0ab2453a210b44656ce976cc67ef3f135c6bcbac5eb73c18bb8235988efd7be7b87acacc0a6bddc76780bcf4e30a055cbbdd5ad12e854e4d3c118150eb0341bdf1d0c8e65085e2f29f6e1ef23c47918446f617a064f388a7c5158f8257c4d0faa83ad6eadecab44c648aaed3bf82d34ebe868b11e3fb39fc8cb2efc9525b60276f489e013e41c7a80a1a89c4389ccd5884df78799b4245bbde567fc2d3f052a5cc66db4c3fdbcb8b5665501dfa64ecbbf06b10203010001a3633061300f0603551d130101ff040530030101ff301d0603551d0e041604142308eb98e259259e5372a7d895e85300c4370070300e0603551d0f0101ff040403020106301f0603551d230418301680142308eb98e259259e5372a7d895e85300c4370070300d06092a864886f70d01010b0500038202010028b86220297d2270beaf3851ba825b05e5b7f8342f6a10438f2fac6449f4cc7379574159305e5af6287b9f31e9c62802d469094ddbef688d1f1971fc2c2dc189e93262e843623031084c1a611a8c00440077bba48cc08907ba86b9b7341203a3edc99b7ac6f5560619f4c364101766d31db081dcec8ed4f24b5f4b693faef231befc5dcf5b70f39c715207dfbfbcaa23bbd14d48e52f604c99a54740328fb81322d8158b59902c8ba77591f5b2507aff6e69288560cfc49c40199e2cc007b8586ed7a32b5284e51834b980b16616e4827097724ff18857b6a63493ccf41f2825f348e5fba817de2558dc65c15db081a6bee6446488357754216819ac66b9a72912d4960f587bc08f80ba288039fb63c04bcd2afbb94ff17a921d23a860f4a7b4bc2aac66547efaf6b943052f3e8773a96e138a638d8bbf2335a3e12f37a3ba6de9026f980a0cb200e7bde4e003f556038613267e892d208f199dc47803ddb2698ca12bb5ab28ae6f4e85ea3d2b0e9a8d195b899f6cd469210f74b4450c9088b5eee3980ab791563fc776f265d7eb98794824b75ba5120d8bd59038193fde9e459512c222ef492a1949f40ee27f807adbf3c9c509f0a71ba4473a58214358fca219a07caa3378424d913ba6beeb8dc7f820d6c2f606cb08a722c58fac5b98b8ff5549d6627b3dbd7b2f1b2be4de1e8ed2555c324eee5f8554e8d38aa9e60003c9" | xxd -r -p | openssl x509 -inform DER> /usr/local/share/ca-certificates/evt-rca.crt && \
  cat /usr/local/share/ca-certificates/evt-rca.crt && \
  update-ca-certificates && \
  keytool -import -trustcacerts -cacerts -storepass changeit -noprompt -alias evt-rca -file /usr/local/share/ca-certificates/evt-rca.crt

WORKDIR /root
