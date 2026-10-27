# Design decisions

Each choice below has a reason and a cost. If you can't explain a row in an interview, read the code for it before you put this project on your CV.

## Network

| Decision | Why | Tradeoff |
|---|---|---|
| 3 subnet tiers × 2 AZs | ALB needs ≥ 2 AZs; RDS subnet group needs ≥ 2 AZs; one instance per AZ survives an AZ failure | More subnets to reason about |
| DB subnets have **no** default route | Isolation by routing, not just firewalling: even a misconfigured SG can't give RDS internet access | RDS can't reach the internet (it doesn't need to) |
| NAT **instance** by default | A NAT Gateway bills hourly plus per GB; a t4g.nano is a small fraction of that | Single point of failure, you patch it, limited bandwidth. Switch with `nat_mode = "gateway"` |
| One NAT, not one per AZ | Cost | If AZ-a dies, AZ-b instances lose outbound internet (but keep serving traffic) |
| S3 gateway endpoint | Free; dnf and SSM-related S3 traffic skips the NAT | None |
| SG rules reference SGs, not CIDRs | ASG instances get random IPs; "anything in the app tier" is the real intent | Harder to read in the console |
| App egress is 443 + 5432 only | Limits what a compromised instance can talk to | Anything new (e.g. SMTP) needs a rule |

## Compute and deploys

| Decision | Why | Tradeoff |
|---|---|---|
| EC2 ASG + Docker, not ECS/EKS | Keeps the focus on networking and Terraform; you see the OS layer | You manage AMI updates and boot scripts |
| Image tag lives in SSM, not in Terraform | CI deploys without running Terraform; `terraform apply` never rolls back a deploy (`ignore_changes`) | Terraform state doesn't show which version is live |
| Deploy = instance refresh | Immutable: every deploy is fresh instances from the same template | Slower than restarting containers in place (~4–6 min) |
| ALB health check on `/health`, not `/ready` | A DB blip would otherwise mark every instance unhealthy and the ASG would replace the whole fleet | ALB may route to an instance whose DB connection is broken; app returns 503 for those requests |
| `health_check_type = "ELB"` | ASG replaces instances whose app is dead, not just instances whose VM is dead | Bad deploys get churned instead of left for debugging |
| IMDSv2 required | Blocks SSRF-style theft of instance credentials | Older tools that use IMDSv1 break |
| `deregistration_delay = 30` | Default 300 s makes every deploy wait 5 minutes per batch | Long requests over 30 s get cut during deploys |

## Data and secrets

| Decision | Why | Tradeoff |
|---|---|---|
| RDS single-AZ by default | Cost | Maintenance or AZ failure = downtime. `db_multi_az = true` fixes it at roughly double cost |
| Password via `random_password` → SSM SecureString | No secrets in GitHub or user-data; instances fetch at boot via IAM | Password is in Terraform state. Hence encrypted private state bucket. Alternative: `manage_master_user_password` (Secrets Manager, extra cost) |
| `create_all()` at startup | Simple | Not real migrations. Production would use Alembic run once by CI |
| `skip_final_snapshot = true` | One-command destroy | You lose data on destroy, intentionally |

## Monitoring

| Decision | Why | Tradeoff |
|---|---|---|
| Prometheus for app metrics, CloudWatch for AWS metrics | ALB/RDS/ASG metrics only exist in CloudWatch; request latency histograms per route only exist in the app | Two systems; Grafana unifies the view |
| Prometheus EC2 service discovery by `Role` tag | New ASG instances get scraped automatically | Needs `ec2:DescribeInstances` |
| Route template as the metric label | Raw paths with session IDs would create a new time series per user (cardinality blowup). Covered by a test | None |
| **Alerts in CloudWatch, not Grafana** | If the monitoring instance dies, CloudWatch alarms still fire. An alerting system that lives on the box it's watching is a classic mistake | Prometheus-only conditions (e.g. p95 latency) aren't alerted on yet — a good next step |
| Grafana via SSM port-forward | No public dashboard to secure | Need the Session Manager plugin to view it |
| `/metrics` blocked at the ALB | Metrics leak internals (routes, error rates) | None |
| Monitoring on t3.small | Prometheus + Grafana on 1 GB is tight (you hit OOM on k3s before) | Slightly higher cost |

## CI/CD

| Decision | Why | Tradeoff |
|---|---|---|
| GitHub OIDC, no AWS keys | Short-lived credentials; nothing to leak or rotate | One-time bootstrap |
| Three roles: plan / apply / deploy | Plan runs on any PR, so it's read-only. Apply is admin but only from the reviewer-protected `production` environment. Deploy can only touch the image param and the ASG | More IAM to understand |
| Plan posted as a PR comment | Review infra changes like code | Long plans get truncated |
| `concurrency` group on Terraform jobs | Two applies at once would fight over state | Jobs queue |

## Rough running cost (ap-south-1, check the AWS Pricing Calculator)

Biggest to smallest, while everything is up: **ALB ≈ RDS > NAT Gateway (if used) > monitoring t3.small > 2 × t3.micro > public IPv4 charges > NAT instance**. Run it for a demo session, then `terraform destroy`. A few hours costs very little; a forgotten month does not.

## Known limitations (be upfront about these)

- HTTP only unless you add an ACM certificate and a domain.
- Single NAT and single-AZ RDS: not highly available by design.
- AMI is resolved at plan time: a new AL2023 release creates a new launch-template version, which triggers a rolling instance refresh of the app tier on the next apply. The NAT and monitoring instances ignore AMI changes and must be replaced deliberately (`terraform apply -replace=...`).
- No WAF, no CloudFront, no backups beyond 1-day automated RDS snapshots.
- Prometheus data is lost if the monitoring instance is replaced.

## Questions an interviewer will ask

1. Why doesn't the DB route table have a NAT route? What would break if it did?
2. What's the difference between a security group and a NACL? Why didn't you use NACLs?
3. Walk through what happens, packet by packet, when a user loads the page.
4. A new app instance boots but never becomes healthy. How do you debug it without SSH?
5. Why is the ALB health check `/health` and not `/ready`?
6. Two engineers run `terraform apply` at the same time. What happens?
7. Someone edits a security group in the console. How do you find out, and what does the next apply do?
8. How would you make this highly available? What does each step cost?
9. Why are alerts in CloudWatch and not Grafana?
10. How would you move this to EKS, and what in this VPC would you reuse?
