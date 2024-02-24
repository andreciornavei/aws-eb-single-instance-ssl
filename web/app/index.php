<?php 

error_reporting(E_ALL);
ini_set('display_errors', 'On');
echo "Hello World - SSL Single Instance";
echo "<br/>";
echo "APP_NAME=" . getenv('APP_NAME') . " | APP_VERSION=" . getenv('APP_VERSION');

?>