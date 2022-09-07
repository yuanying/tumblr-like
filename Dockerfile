# docker build -t yuanying/tumblr-like .
# docker run -d -v /volumes/downloads:/usr/src/app/contents yuanying/tumblr-like
FROM ruby:2.5-slim as builder

RUN apt update
RUN apt install -y build-essential \
    libfreeimage-dev \
    libcurl4
ENV BUNDLER_VERSION 2.0.1
RUN gem install bundler
WORKDIR /tmp
COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock
ENV BUNDLE_JOBS=4
RUN bundle install

FROM ruby:2.5-slim
MAINTAINER O. Yuanying "yuan-docker@fraction.jp"

ENV BUNDLER_VERSION 2.0.1
RUN gem install bundler
WORKDIR /tmp
COPY Gemfile Gemfile
COPY Gemfile.lock Gemfile.lock
COPY --from=builder /usr/local/bundle /usr/local/bundle

ENV APP_HOME /usr/src/app
RUN mkdir -p $APP_HOME
WORKDIR $APP_HOME
COPY . $APP_HOME

VOLUME ["/usr/src/app/contents"]

ENV TUMBLR_CONSUMER_KEY "XXXXX"
ENV TUMBLR_CONSUMER_SECRET "XXXXX"
ENV TUMBLR_CONSUMER_TOKEN "XXXXX"
ENV TUMBLR_CONSUMER_TOKEN_SECRET "XXXXX"

CMD ["bundle", "exec", "ruby", "download.rb"]
