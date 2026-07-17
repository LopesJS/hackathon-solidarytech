output "volunteer_matches_table_name" { value = aws_dynamodb_table.volunteer_matches.name }
output "donation_events_table_name"   { value = aws_dynamodb_table.donation_events.name }
output "volunteer_matches_arn"        { value = aws_dynamodb_table.volunteer_matches.arn }
output "donation_events_arn"          { value = aws_dynamodb_table.donation_events.arn }
