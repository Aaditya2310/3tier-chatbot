"""LLM abstraction. Rule-based by default (no API key, no cost).
Set LLM_PROVIDER=anthropic and ANTHROPIC_API_KEY to use Claude."""
import os

RULES = {
    "terraform": "Terraform describes infrastructure as code. Run `terraform plan` before every apply and keep state remote with locking.",
    "vpc": "A VPC is your private network in AWS. This project uses public subnets for the ALB, private subnets for the app, and isolated subnets for the database.",
    "nat": "A NAT lets private instances reach the internet outbound without being reachable inbound. A NAT Gateway bills hourly; a NAT instance is cheaper but you manage it.",
    "security group": "Security groups are stateful firewalls. Here the DB only accepts traffic from the app's security group, not from an IP range.",
    "docker": "Docker packages the app with its dependencies so it runs the same on your laptop and on EC2.",
    "kubernetes": "Kubernetes orchestrates containers. This project deliberately uses EC2 Auto Scaling instead, to focus on AWS networking.",
    "prometheus": "Prometheus scrapes /metrics from each app instance, which it discovers through the EC2 API by tag.",
    "grafana": "Grafana shows Prometheus (app metrics) and CloudWatch (ALB, RDS) on one dashboard.",
    "autoscaling": "The Auto Scaling Group adds instances when ALB requests per target rise, and replaces unhealthy ones.",
    "rds": "RDS runs managed Postgres. It sits in subnets with no route to the internet.",
}
FALLBACK = ("I'm Patch, a rule-based DevOps assistant. Ask me about terraform, vpc, nat, "
            "security groups, docker, kubernetes, prometheus, grafana, autoscaling or rds.")


class RuleBasedProvider:
    name = "rule-based"

    def reply(self, message: str) -> str:
        lower = message.lower()
        for key, answer in RULES.items():
            if key in lower:
                return answer
        return FALLBACK


class AnthropicProvider:
    name = "anthropic"

    def __init__(self) -> None:
        import anthropic  # imported lazily so the default image doesn't need it at runtime
        self.client = anthropic.Anthropic()
        self.model = os.getenv("ANTHROPIC_MODEL", "claude-haiku-5-5")

    def reply(self, message: str) -> str:
        try:
            resp = self.client.messages.create(
                model=self.model, max_tokens=400,
                system="You are Patch, a concise DevOps assistant inside TriTier ChatOps.",
                messages=[{"role": "user", "content": message}],
            )
            return resp.content[0].text
        except Exception:  # noqa: BLE001 — degrade instead of failing the request
            return RuleBasedProvider().reply(message)


def get_provider():
    if os.getenv("LLM_PROVIDER", "rule-based") == "anthropic" and os.getenv("ANTHROPIC_API_KEY"):
        return AnthropicProvider()
    return RuleBasedProvider()
