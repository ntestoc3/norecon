
# 主域名信息

{# [[{{ target }}]] #}

| 域名 | http信息 | ip信息 |
| ---- | ---- | ---- |
{% for d in data -%}
  |[[{{ d['domain'] }}]] |
  {%- if d['http-info'] -%} <table> <tr> <th>url</th> <th>标题</th> <th>tags</th> <th>状态</th> </tr>
    {%- for hinfo in d['http-info'] -%}
      <tr> <td> {{ hinfo['url'] }} </td> <td>
{%- autoescape true -%}
      {{ hinfo['title']|replace("|", "")|replace("\n", "")|replace("\r", "")|truncate(50, True) }} 
{%- endautoescape -%}
      </td> <td>
          {%- if hinfo['tags'] -%}
            {%- for t in hinfo['tags'] -%}
              <li> [{{ t['text']|replace("|", "")|truncate(27, True) }}]({{ t['link'] }}) </li>
            {%- endfor -%}
          {%- endif -%}
        </td> <td> {{ hinfo['status'] }} </td> </tr>
    {%- endfor -%}
    </table>
  {%- endif -%} |
  {%- if d['ip-info'] -%} <table><tr><th>ip</th><th>网络名</th><th>位置</th></tr>
      {%- for ip in d['ip-info'] -%}
        <tr><td>[[{{ ip['ip'] }}]]</td><td>{{ ip['net-name'] }}<td>{{ ip['location'] }}</td></tr>
      {%- endfor -%}
    </table>
  {%- endif -%} |
{% endfor %}
