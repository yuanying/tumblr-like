# docker build -t ghcr.io/yuanying/tumblr-like .
# docker run -d -v /volumes/downloads:/usr/src/app/contents ghcr.io/yuanying/tumblr-like
FROM ruby:4.0-slim AS builder

# git fetches tumblr_client, which is pinned to a tag on GitHub.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp
COPY Gemfile Gemfile.lock ./
# Fail rather than resolve again when Gemfile.lock does not match Gemfile.
ENV BUNDLE_JOBS=4 BUNDLE_FROZEN=true
RUN bundle install

FROM ruby:4.0-slim
LABEL org.opencontainers.image.source="https://github.com/yuanying/tumblr-like" \
      maintainer="O. Yuanying <yuan-docker@fraction.jp>"

COPY --from=builder /usr/local/bundle /usr/local/bundle

ENV APP_HOME /usr/src/app
WORKDIR $APP_HOME
COPY . $APP_HOME

VOLUME ["/usr/src/app/contents"]

ENV TUMBLR_CONSUMER_KEY "XXXXX"
ENV TUMBLR_CONSUMER_SECRET "XXXXX"
ENV TUMBLR_CONSUMER_TOKEN "XXXXX"
ENV TUMBLR_CONSUMER_TOKEN_SECRET "XXXXX"

CMD ["bundle", "exec", "ruby", "download.rb"]
