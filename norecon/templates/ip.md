
# ip信息

{% if data['host'] %}
域名: {{ data['host'] }}
{% endif %}
{% if data['cdn-type'] %}
cdn类型: {{ data['cdn-type'] }}
{% endif %}
{% if data['net-name'] %}
网络名: {{ data['net-name'] }}
{% endif %}
{% if data['location'] %}
位置: {{ data['location'] }}
{% endif %}

| 端口　 |  协议 |  服务类型　| 产品　|
| ----  | ---- | ---- | ---- |
{% for p in data['ports'] -%}
| {{ p['port'] }} | {{ p['protocol'] }} | {{ p['service']['type'] }} | {{ p['service']['product'] }} |
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

# 原始数据
```json
{{ data | pprint() }}
```
