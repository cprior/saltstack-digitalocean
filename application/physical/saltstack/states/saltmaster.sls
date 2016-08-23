The inotify beacon requires Pyinotify:
  pkg.installed:
    - name: python-pyinotify

{% for dir in ['cloud.d', 'cloud.maps.d', 'cloud.profiles.d', 'cloud.providers.d', 'master.d','minion.d'] %}
{{ dir }}:
  file.recurse:
    - name: /etc/salt/{{ dir }}
    - source: salt://{{ dir }}
{% endfor %}

salt-master:
  service.running:
    - enable: True
    - name: salt-master
    - watch:
      - file: /etc/salt/*
