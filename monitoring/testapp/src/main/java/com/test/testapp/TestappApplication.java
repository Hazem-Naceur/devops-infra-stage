package com.test.testapp;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class TestappApplication {
    public static void main(String[] args) {
        SpringApplication.run(TestappApplication.class, args);
    }

    @GetMapping("/hello")
    public String hello() {
        return "ok";
    }
}
