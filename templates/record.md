
# 子域名信息

{# [[{{ target }}]] #}

| 别名　| 类型　| 过期时间　| 结果　|
| ---- | ---- | ---- | ---- |
{% for d in data -%}
  | {{ d['canonical-name'] }} | {{ d['type'] }} | {{ d['expiration'] }} |
  {%- for l in d['result'] %}
    {%- if d['type'] == 'A' %}
      <li> [[{{ l }}]] </li>
    {%- else %}
      <li> {{ l }} </li>
    {%- endif %}
  {%- endfor %}
{% endfor %}

{% if screen %}

# 屏幕快照
  {% for s in screen %}
## {{ s['target'] }}

### http头

| 名字 | 值 |
| ---- | ---- |
    {% for h in s['headers'] -%}
      {% if h['decreasesSecurity'] -%}
        | <span style="color:red">{{ h['name'] }}</span> | <span style="color:red">{{ h['value'] }}</span> | 
      {% elif h['increasesSecurity'] -%}
        | <span style="color:green">{{ h['name'] }}</span> | <span style="color:green">{{ h['value'] }}</span> | 
      {% else -%}
        | {{ h['name'] }} | {{ h['value'] }} |
      {% endif %}
    {% endfor %}

### ip地址

    {% for ip in s['addrs'] -%}
      - [[{{ip}}]]
    {% endfor %}

<center> <h5>{{ s['pageTitle'] }} </h5> {{ s['status'] }} </center>

![快照]({{ s['screenshotPath'] }})

******
  {% endfor %}
{% endif %}
