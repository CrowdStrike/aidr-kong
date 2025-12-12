# Dockerfile for use Kong Gateway
# with CrowdStrike AIDR plugins built from repository files

# Use the official Kong Gateway image as a base
FROM kong/kong-gateway:latest

# Ensure any patching steps are executed as root user
USER root

# Copy plugin code and rockspecs into the same folder
COPY ./kong /kong
COPY ./kong-plugin-crowdstrike-aidr-*.rockspec /

# Build from local rockspecs
RUN luarocks make kong-plugin-crowdstrike-aidr-shared-*.rockspec \
  && luarocks make kong-plugin-crowdstrike-aidr-request-*.rockspec \
  && luarocks make kong-plugin-crowdstrike-aidr-response-*.rockspec

# Specify the plugins to be loaded by Kong,
# including the default bundled plugins and the CrowdStrike AIDR plugins
ENV KONG_PLUGINS=bundled,crowdstrike-aidr-request,crowdstrike-aidr-response

# Ensure kong user is selected for image execution
USER kong

# Run kong
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 8000 8443 8001 8444
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=10s --timeout=10s --retries=10 CMD kong health
CMD ["kong", "docker-start"]
