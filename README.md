webapollo-docker
====================

Introduction
------------

This Dockerfile template (and associated scripts) can be used to help groups set up their own webapollo instances, running as isolated docker containers.


Using the pre-built image
-------------------------

Pull down the image and run it:

    docker pull robsyme/webapollo
    docker run -d robsyme/webapollo -p 80:8080

Using the Dockerfile
--------------------

This Dockerfile downloads the example dataset, which is of use to very few people. In reality, I expect most people to fork this repository and add their own data. You can view the other [github.com/robsyme/webapollo-docker](http://github.com/robsyme/webapollo-docker/)  branches to see how I am using this template for our own genomes.
