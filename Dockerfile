# Dockerfile for use Kong Gateway
# with CrowdStrike AIDR plugins built from repository files
#
# Build for standard Kong Gateway (default):
#   docker build -t kong-aidr .
#
# Build for Kong AI Gateway 2.x:
#   docker build --build-arg BASE_IMAGE=kong/kong-ai-gateway:latest -t kong-aidr-ai-gateway-2 .

ARG BASE_IMAGE=kong/kong-gateway:latest

# Use the official Kong Gateway image as a base
FROM ${BASE_IMAGE}

# Ensure any patching steps are executed as root user
USER root

# Copy plugin code and rockspecs into the same folder
COPY ./kong /kong
COPY ./kong-plugin-crowdstrike-aidr-*.rockspec /

# Build from local rockspecs
RUN for rs in kong-plugin-crowdstrike-aidr-shared-*.rockspec; do luarocks make "$rs"; done \
  && for rs in kong-plugin-crowdstrike-aidr-request-*.rockspec; do luarocks make "$rs"; done \
  && for rs in kong-plugin-crowdstrike-aidr-response-*.rockspec; do luarocks make "$rs"; done \
  && for rs in kong-plugin-crowdstrike-aidr-mcp-*.rockspec; do luarocks make "$rs"; done

# Specify the plugins to be loaded by Kong,
# including the default bundled plugins and the CrowdStrike AIDR plugins
ENV KONG_PLUGINS=bundled,crowdstrike-aidr-request,crowdstrike-aidr-response,crowdstrike-aidr-mcp

# Ensure kong user is selected for image execution
USER kong

# Run kong
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 8000 8443 8001 8444
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=10s --timeout=10s --retries=10 CMD kong health
CMD ["kong", "docker-start"]
