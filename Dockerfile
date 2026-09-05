FROM ruby:3.2-slim

RUN apt-get update && apt-get install -y build-essential git && rm -rf /var/lib/apt/lists/*
WORKDIR /app

RUN gem install bundler rspec rubocop
CMD ["bash"]