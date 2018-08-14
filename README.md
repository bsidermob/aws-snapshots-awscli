# AWS EC2 volumes snapshot script

This executes snapshot creation of EC2 instances which have termination protection on.
It's sort of an expirement of using AWS CLI in Lambda. It doesn't work very well
as it takes too long to run and it doesn't finish in Lambda's 5 minute
limit if you've got lots of volumes. It was fun experimenting with it though.
