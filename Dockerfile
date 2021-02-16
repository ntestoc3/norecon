FROM python:3.7-slim-buster

WORKDIR /app
COPY dist/* /app/

RUN apt-get update && \
  apt-get install -y --no-install-recommends masscan nmap && \
  apt-get install -y --no-install-recommends libxml2-dev libxslt-dev zlib1g-dev python3.7-dev gcc && \
  pip3 install --no-cache-dir /app/*.whl && \
  apt-get remove --purge --auto-remove -y libxml2-dev libxslt-dev zlib1g-dev python3.7-dev gcc && \
  rm -r /var/lib/apt/lists/*

# RUN setcap cap_net_raw=eip /usr/bin/masscan
# RUN setcap cap_net_raw=eip /usr/bin/nmap

RUN echo "downloading amass..." && \
  apt-get update && \
  apt-get install -y --no-install-recommends ca-certificates curl bsdtar && \
  curl -SL https://github.com/OWASP/Amass/releases/latest/download/amass_linux_amd64.zip | \
  bsdtar -xf- -C /tmp && \
  chmod +x /tmp/amass_linux_amd64/amass && \
  mv /tmp/amass_linux_amd64/amass /usr/local/bin/ && \
  echo "downloading aquatone..." && \
  curl -SL  https://github.com/ntestoc3/aquatone/releases/latest/download/aquatone_linux_amd64_1.7.1.zip | \
  bsdtar -xf- -C /tmp && \
  chmod +x /tmp/aquatone && \
  mv -f /tmp/aquatone /usr/local/bin/ && \
  rm -rf /tmp/* && \
  rm -rf /app/* && \
  curl -SL -o /usr/local/bin/findomain https://github.com/Findomain/Findomain/releases/latest/download/findomain-linux && \
  apt-get remove --purge --auto-remove -y ca-certificates curl bsdtar && \
  rm -r /var/lib/apt/lists/*


ENV PATH=/usr/local/bin:$PATH
# docker镜像里不安装chrome,使用远程devtools
ENV USE_CHROME_REMOTE=true

WORKDIR /data

# make docker container running
CMD tail -f /dev/null

