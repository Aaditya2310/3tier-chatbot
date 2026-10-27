global:
  scrape_interval: 15s
scrape_configs:
  - job_name: chatops-app
    metrics_path: /metrics
    ec2_sd_configs:
      - region: ${region}
        port: 8000
        filters:
          - name: tag:Role
            values: ["${project}-app"]
          - name: instance-state-name
            values: ["running"]
    relabel_configs:
      # Scrape the private IP (we're inside the VPC) and label series by instance id.
      - source_labels: [__meta_ec2_private_ip]
        replacement: "$1:8000"
        target_label: __address__
      - source_labels: [__meta_ec2_instance_id]
        target_label: instance
      - source_labels: [__meta_ec2_availability_zone]
        target_label: az
