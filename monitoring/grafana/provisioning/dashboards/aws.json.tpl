{
  "uid": "chatops-aws",
  "title": "ChatOps \u2014 AWS tiers (CloudWatch)",
  "schemaVersion": 39,
  "refresh": "1m",
  "time": {
    "from": "now-3h",
    "to": "now"
  },
  "tags": [
    "chatops"
  ],
  "panels": [
    {
      "id": 1,
      "title": "ALB requests",
      "type": "timeseries",
      "gridPos": {
        "x": 0,
        "y": 0,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "short"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/ApplicationELB",
          "metricName": "RequestCount",
          "dimensions": {
            "LoadBalancer": "${alb_dimension}"
          },
          "statistic": "Sum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    },
    {
      "id": 2,
      "title": "ALB 5xx (ELB + targets)",
      "type": "timeseries",
      "gridPos": {
        "x": 12,
        "y": 0,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "short"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/ApplicationELB",
          "metricName": "HTTPCode_ELB_5XX_Count",
          "dimensions": {
            "LoadBalancer": "${alb_dimension}"
          },
          "statistic": "Sum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        },
        {
          "refId": "B",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/ApplicationELB",
          "metricName": "HTTPCode_Target_5XX_Count",
          "dimensions": {
            "LoadBalancer": "${alb_dimension}"
          },
          "statistic": "Sum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    },
    {
      "id": 3,
      "title": "Healthy / unhealthy targets",
      "type": "timeseries",
      "gridPos": {
        "x": 0,
        "y": 8,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "short"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/ApplicationELB",
          "metricName": "HealthyHostCount",
          "dimensions": {
            "LoadBalancer": "${alb_dimension}",
            "TargetGroup": "${tg_dimension}"
          },
          "statistic": "Minimum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        },
        {
          "refId": "B",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/ApplicationELB",
          "metricName": "UnHealthyHostCount",
          "dimensions": {
            "LoadBalancer": "${alb_dimension}",
            "TargetGroup": "${tg_dimension}"
          },
          "statistic": "Maximum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    },
    {
      "id": 4,
      "title": "Target response time",
      "type": "timeseries",
      "gridPos": {
        "x": 12,
        "y": 8,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "s"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/ApplicationELB",
          "metricName": "TargetResponseTime",
          "dimensions": {
            "LoadBalancer": "${alb_dimension}"
          },
          "statistic": "Average",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    },
    {
      "id": 5,
      "title": "RDS CPU",
      "type": "timeseries",
      "gridPos": {
        "x": 0,
        "y": 16,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "percent"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/RDS",
          "metricName": "CPUUtilization",
          "dimensions": {
            "DBInstanceIdentifier": "${db_identifier}"
          },
          "statistic": "Average",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    },
    {
      "id": 6,
      "title": "RDS connections",
      "type": "timeseries",
      "gridPos": {
        "x": 12,
        "y": 16,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "short"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/RDS",
          "metricName": "DatabaseConnections",
          "dimensions": {
            "DBInstanceIdentifier": "${db_identifier}"
          },
          "statistic": "Maximum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    },
    {
      "id": 7,
      "title": "RDS free storage",
      "type": "timeseries",
      "gridPos": {
        "x": 0,
        "y": 24,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "bytes"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/RDS",
          "metricName": "FreeStorageSpace",
          "dimensions": {
            "DBInstanceIdentifier": "${db_identifier}"
          },
          "statistic": "Minimum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    },
    {
      "id": 8,
      "title": "ASG in-service instances",
      "type": "timeseries",
      "gridPos": {
        "x": 12,
        "y": 24,
        "w": 12,
        "h": 8
      },
      "datasource": {
        "type": "cloudwatch",
        "uid": "cloudwatch"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "short"
        },
        "overrides": []
      },
      "targets": [
        {
          "refId": "A",
          "datasource": {
            "type": "cloudwatch",
            "uid": "cloudwatch"
          },
          "namespace": "AWS/AutoScaling",
          "metricName": "GroupInServiceInstances",
          "dimensions": {
            "AutoScalingGroupName": "${asg_name}"
          },
          "statistic": "Maximum",
          "region": "default",
          "matchExact": true,
          "queryMode": "Metrics",
          "metricQueryType": 0,
          "metricEditorMode": 0,
          "id": "",
          "expression": "",
          "period": ""
        }
      ]
    }
  ]
}