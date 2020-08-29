
# Whois信息

{% if data['domain_name'] %}
[[domain/{{ target }}]]
{% else %}
[[ip/{{ target }}]]
{% endif %}

```json
{{ data | pprint() }}
```
