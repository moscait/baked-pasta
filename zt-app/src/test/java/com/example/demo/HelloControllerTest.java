package com.example.demo;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(HelloController.class)
class HelloControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    @DisplayName("returns default greeting when name is absent")
    void sayHello_noName_returnsHelloWorld() throws Exception {
        mockMvc.perform(get("/hello"))
                .andExpect(status().isOk())
                .andExpect(content().string("Hello world!"));
    }

    @Test
    @DisplayName("serves text/plain even when a browser asks for HTML (prevents reflected XSS)")
    void sayHello_browserAcceptHeader_isServedAsPlainText() throws Exception {
        mockMvc.perform(get("/hello")
                        .param("name", "<script>alert(1)</script>")
                        .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"))
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.TEXT_PLAIN));
    }

    @Test
    @DisplayName("truncates overly long names")
    void sayHello_longName_isTruncated() throws Exception {
        String longName = "a".repeat(500);
        mockMvc.perform(get("/hello").param("name", longName))
                .andExpect(status().isOk())
                .andExpect(content().string("Hello, " + "a".repeat(100) + "!"));
    }
}
