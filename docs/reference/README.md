# RomM API snapshot

Follow-up: the [initial application client](../romm-application.md) now verifies the public heartbeat directly over validated HTTPS at `https://romm.docubi.casa`, reporting 5.4.0 without the proxy. This does not change the provenance/hash of the captured schema below. Owner-authenticated catalogue/login acceptance remains pending.

The [OpenAPI snapshot](romm-5.4.0-openapi.json) was retrieved from the owner's instance on 2026-10-16 using a read-only, unauthenticated request:

```sh
curl --proxy http://192.168.1.2:1080 \
  --connect-timeout 8 --max-time 25 \
  --output /tmp/broomm-romm-openapi.json \
  http://romm.docubi.casa/openapi.json
```

The request returned HTTP 200 and JSON with title `RomM API`, version `5.4.0`, OpenAPI `3.1.0`, and 226 paths. The snapshot contains 494,320 bytes. SHA-256:

```text
ce59cca7062a05d7e63a93f3f6da896dd42604e87494055ca05e473b5287d43b
```

The supplied endpoint worked as an HTTP forward proxy. SOCKS5 negotiation failed and HTTPS CONNECT returned 405; this check does not establish HTTPS connectivity or change Broomm's TLS policy. Network access required execution outside the tool sandbox. The proxy address is a local investigation aid, not an application default.

No credentials were sent and no authenticated catalogue, launch, download or save-sync behavior was exercised. Schema retrieval confirms the served API version and provides an instance-specific contract reference; runtime integration and race/conflict behavior still need validation.
