FROM ruby:3.3-slim

RUN apt-get update && apt-get install -y build-essential git && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Кэшируем установку гемов
COPY Gemfile Gemfile.lock* ./
RUN gem install bundler && bundle install

# Копируем исходный код
COPY . .

# Выдаем права на исполнение
RUN chmod +x ./bin/integrate

CMD ["bash"]