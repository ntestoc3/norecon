
# Whois信息

{% if data['domain_name'] %}
[[{{ target }}]]
{% else %}
[[{{ target }}]]
{% endif %}

```json
{{ data | pprint() }}
```
