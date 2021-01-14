FROM amazon/aws-cli
COPY capture-awspbmmaccelerator-prescribed-infrastructure /tmp/capture-awspbmmaccelerator-prescribed-infrastructure
RUN yum install -y jq bind-utils; \
    chmod +x /tmp/capture-awspbmmaccelerator-prescribed-infrastructure
ENTRYPOINT ["/tmp/capture-awspbmmaccelerator-prescribed-infrastructure"]