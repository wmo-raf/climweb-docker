# Setup Observability (Logging + Metrics) - optional

ClimWeb uses [OpenTelemetry](https://opentelemetry.io/) to collect logs and metrics. The `docker-compose.yml` file includes an [opentelemetry-collector](https://opentelemetry.io/docs/collector/) that provides a vendor-agonistic way to gather observability data.

A default configuration that uses the [Honeycomb](https://www.honeycomb.io/) platform is provided. Honeycomb provides a generous free tier to get you started. 

Custom collectors can be used by setting the collector endpoint env variable `OTEL_EXPORTER_OTLP_ENDPOINT` and commenting out the `climweb_otel_collector` service, or configuring the `climweb_otel_collector` to what suits you.

To use the default setup, create a [free Honeycomb account](https://ui.honeycomb.io/signup) and get your API Key from `Account > Team Settings` menu


Update `.env` as below

```
nano .env
```

```env
CLIMWEB_ENABLE_OTEL=True
HONEYCOMB_API_KEY=
```

Then restart climweb with this commands

```bash
make restart
```
