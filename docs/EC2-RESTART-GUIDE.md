# EC2 Restart & Project Recovery Guide

## Project

Three-Tier React + Node.js + MongoDB application deployed on AWS EKS.

Public application:

https://www.qrmake.shop

AWS Region:

us-west-2

EKS Cluster:

three-tier-cluster

Kubernetes Namespace:

three-tier

---

## 1. Important Architecture

The EC2 instance is mainly used as the management/deployment machine.

The application itself runs inside AWS EKS.

```text
EC2
 |
 | kubectl / AWS CLI
 v
EKS Cluster
 |
 +-- Frontend
 +-- Backend
 +-- MongoDB
 |
 +-- EBS persistent storage
 |
 v
AWS Load Balancer
 |
 v
https://www.qrmake.shop
