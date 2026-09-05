# Grafana with Pulse's SLO burn-rate dashboard baked in (Phase 11) - a
# dashboard-as-code, not something clicked together once in the UI and lost
# on the next task replacement (Grafana's own SQLite state doesn't survive
# a Fargate task restart anyway - see terraform/README.md).
FROM grafana/grafana:11.3.0

USER root
COPY docker/grafana/provisioning/dashboards /etc/grafana/provisioning/dashboards
COPY docker/grafana/dashboards /var/lib/grafana/dashboards
COPY docker/grafana/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    # entrypoint.sh (still running as the grafana user below) regenerates this
    # file from the task's environment at container start - it needs to be
    # writable by that user, not just root at build time. The grafana user's
    # actual group is root/gid 0 in this base image (confirmed via `id`), not
    # a "grafana" group - `chown grafana:grafana` fails outright.
    && chown grafana:root /etc/grafana/provisioning/datasources

USER grafana
ENTRYPOINT ["/entrypoint.sh"]
