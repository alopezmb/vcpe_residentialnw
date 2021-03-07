FROM vyos/rolling:1.3
RUN mkdir /config

COPY ipv6_conf .
RUN cat ipv6_conf >> /etc/sysctl.conf
RUN rm ipv6_conf

CMD /sbin/init
