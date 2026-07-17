output "donations_queue_url"              { value = aws_sqs_queue.donations.id }
output "donations_queue_arn"              { value = aws_sqs_queue.donations.arn }
output "dlq_url"                          { value = aws_sqs_queue.dlq.id }
output "dlq_arn"                          { value = aws_sqs_queue.dlq.arn }
output "volunteer_notifications_queue_url"{ value = aws_sqs_queue.volunteer_notifications.id }
