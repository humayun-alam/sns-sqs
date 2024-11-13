variable "environment" {
    default = "test"
}

variable "enable_set_attributes" {
  description = "Should the created iam user be permitted to set queue attributes"
  default     = true
}

variable "cidr_blocks" {
  description = "A list of network cidr blocks which are permitted access"
  default     = []
}