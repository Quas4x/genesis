# genesis
# 🚀 Space Payments: OpenAPI Integration Generator

**Hack.Genesis 2026 | Трек: API Integration Generator (Ruby)**  
**Команда:** c0d3R5 | Вячеслав Нестеров

Консольная утилита для автоматизации подключения новых платежных шлюзов к платформе Space Payments. Инструмент парсит спецификации OpenAPI 3.x, нормализует данные и генерирует готовый к бою Ruby-код, документацию и тестовые фикстуры, сокращая время интеграции нового провайдера с нескольких дней до считанных минут.

---

## Бизнес-задача и Решение

Вместо хардкода под конкретный YAML, реализован **универсальный 3-этапный конвейер (Pipeline)**:

1. **Parser & RefResolver:** Читает спецификацию и рекурсивно разрешает внутренние ссылки (`$ref`). Извлекает механизмы авторизации, пути эндпоинтов, лимиты сумм и параметры вебхуков.
2. **Intermediate Representation (IR Model):** Изолирует парсер от генератора. Нормализует внешние статусы (например, `pending` → `in_progress`), маппит HTTP-коды в системные ошибки Space Payments и переводит суммы (копейки → рубли).
3. **Template Engine (ERB):** На основе IR-модели генерирует строго типизированные артефакты, соответствующие внутренним контрактам платформы.

## Инженерные особенности
* **Zero Heavy Dependencies:** Разрешение `$ref` и анализ OpenAPI написаны с нуля без использования тяжеловесных сторонних гемов. Только стандартная библиотека (`yaml`, `erb`, `optparse`).
* **Test-Driven Development (TDD):** Спроектировано через тесты. 100% стабильность работы CLI и парсера покрыта RSpec (включая краш-тесты битого синтаксиса).
* **Соблюдение контракта:** Сгенерированный код полностью наследует логику `Provider::BaseService` и включает методы `create_request`, `fetch_status`, `process_callback` и `check_conditions`.

---

## Установка и запуск

**Требования:**
* Ruby 3.3+
* Bundler

**1. Клонирование и установка зависимостей**
```bash
git clone <репозиторий>
cd genesis
bundle install
```

**2. Использование**
```bash
./bin/integrate --spec "yaml файл провайдера" --provider "название провайдера" --lang "язык"
```
Например: 
```bash
./bin/integrate --spec provider_api.yaml --provider novapay --lang ruby
```

**3. На выходе**
```bash
Parsing spec...
Found 5 endpoints: POST /payouts, GET /payouts/{payout_id}, POST /payouts/{payout_id}/cancel, POST /webhooks/payout, GET /balance
Auth: ApiKeyAuth (header: X-API-Key)
Webhook signature: X-NovaPay-Signature (HMAC-SHA256)
Generating service...
Generating integration guide...
Generating test fixtures...
Output:
  ./output/novapay_service.rb
  ./output/INTEGRATION.md
  ./output/fixtures.json
```

## *Проект покрыт модульными тестами с использованием RSpec. Для прогона всего набора выполните:
```bash
bundle exec rspec
```

## В ближайших итерациях планируется:

Внедрение эвристического поиска эндпоинтов (распознавание методов создания выплаты без жесткой привязки к пути /payouts).

Расширение поддержки схем авторизации (Bearer/JWT, Basic Auth).

Динамическая генерация данных для fixtures.json на основе типов данных из схемы properties, если секция examples отсутствует в спецификации.
