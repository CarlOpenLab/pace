package pace.app.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AiProvidersTest {

    @Test
    fun normalize_strips_trailing_slashes_and_chat_suffix() {
        assertEquals("https://api.deepseek.com/v1", AiProvider.normalize("https://api.deepseek.com/v1/"))
        assertEquals(
            "https://api.deepseek.com/v1",
            AiProvider.normalize("https://api.deepseek.com/v1/chat/completions/")
        )
        assertEquals("https://api.deepseek.com/v1", AiProvider.normalize("  HTTPS://API.DEEPSEEK.COM/V1 "))
        assertEquals("", AiProvider.normalize(""))
    }

    @Test
    fun matching_full_path_matches_preset() {
        assertEquals("deepseek", AiProvider.matching("https://api.deepseek.com/v1/chat/completions").id)
        assertEquals("deepseek", AiProvider.matching("https://api.deepseek.com/v1").id)
        assertEquals("custom", AiProvider.matching("https://my-own.example.com/v1").id)
        assertEquals("custom", AiProvider.matching("").id)
    }

    @Test
    fun chat_and_models_urls_append_paths() {
        assertEquals(
            "https://api.deepseek.com/v1/chat/completions",
            AiProvider.chatUrl("https://api.deepseek.com/v1")
        )
        assertEquals(
            "https://api.deepseek.com/v1/chat/completions",
            AiProvider.chatUrl("https://api.deepseek.com/v1/")
        )
        assertEquals("https://api.deepseek.com/v1/models", AiProvider.modelsUrl("https://api.deepseek.com/v1"))
        assertNull(AiProvider.chatUrl(""))
        assertNull(AiProvider.chatUrl("ftp://nope"))
    }

    @Test
    fun model_ids_parse_three_shapes() {
        assertEquals(
            listOf("m1", "m2"),
            AiModelList.parseIds("{\"data\":[{\"id\":\"m1\"},{\"id\":\"m2\"}]}")
        )
        assertEquals(
            listOf("m1", "m2"),
            AiModelList.parseIds("{\"models\":[{\"id\":\"m1\"},{\"name\":\"m2\"}]}")
        )
        assertEquals(listOf("m1", "m2"), AiModelList.parseIds("[\"m1\",\"m2\"]"))
        assertEquals(emptyList<String>(), AiModelList.parseIds("not json"))
        // 去重、去空白
        assertEquals(listOf("m1"), AiModelList.parseIds("{\"data\":[{\"id\":\"m1\"},{\"id\":\" m1 \"}]}"))
    }
}
