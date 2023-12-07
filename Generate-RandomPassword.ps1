$length = 25
$characters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#$%^&*()'
$password = -join (Get-Random -InputObject $characters.ToCharArray() -Count $length)
$password
