package com.example.demo;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.view.RedirectView;

@RestController
public class HelloController {

    private static final int MAX_NAME_LENGTH = 100;

    @GetMapping("/")
    public RedirectView redirectToSwaggerUi() {
        return new RedirectView("/swagger-ui.html");
    }

    /**
     * Always served as text/plain so a reflected {@code name} can never be
     * interpreted as HTML by a browser (prevents reflected XSS).
     */
    @GetMapping(value = "/hello", produces = MediaType.TEXT_PLAIN_VALUE)
    public String sayHello(@RequestParam(required = false) String name) {
        if (name == null || name.isBlank()) {
            return "Hello world!";
        }
        String trimmed = name.strip();
        String safeName = trimmed.length() > MAX_NAME_LENGTH ? trimmed.substring(0, MAX_NAME_LENGTH) : trimmed;
        return "Hello, " + safeName + "!";
    }
}
