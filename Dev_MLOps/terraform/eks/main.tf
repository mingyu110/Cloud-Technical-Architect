module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "mlops-cluster"
  cluster_version = "1.29"
  subnet_ids      = [var.subnet_id]
  vpc_id          = var.vpc_id

  node_groups = {
    default = {
      desired_capacity = 2
      max_capacity     = 3
      min_capacity     = 1

      instance_types = ["t3.medium"]
    }
  }
}
