-- Create an admin user that will populate the database
CREATE USER web_apollo_users_admin WITH PASSWORD 'AdminPassword' CREATEDB;

-- Create a database that will be used to hold users
CREATE DATABASE web_apollo_users OWNER web_apollo_users_admin
