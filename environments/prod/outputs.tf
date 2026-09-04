output "account_id" {
  description = "Account this root manages. Proves the CI credential path is live while the root is otherwise empty."
  value       = data.aws_caller_identity.current.account_id
}
