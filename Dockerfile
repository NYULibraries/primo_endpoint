FROM haskell:8.4.3
LABEL application="primo-endpoint" url="http://github.com/NYULibraries/primo-endpoint"
EXPOSE 80
RUN apt-get update && \
    apt-get install -y libicu-dev && \
    apt-get autoremove --purge -y && \
    apt-get autoclean -y && \
    rm -rf /var/cache/apt/* /var/lib/apt/lists/*

VOLUME /cache
WORKDIR /app
COPY . /app
RUN stack install --system-ghc && \
  rm -rf .stack-work ~/.stack

ENTRYPOINT ["/root/.local/bin/primo-endpoint", "-C", "/cache", "-w"]
CMD ["-l", "-v"]
