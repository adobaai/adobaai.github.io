# Ai for adobaro

## Technology Stack
- [Chatgpt]
- [Whisper] 

## Chatgpt
> ChatGPT is a sibling model to [InstructGPT], 
> which is trained to follow an instruction in a prompt and provide a detailed response.

### Translation
Because our products are aimed at foreign creator, so the first thing is translation.
Due to Chatgpt has excellent translation effort, we chose it as out translation engine.
We use it to translate information about creator things and srt file.
In addition to it we will also use [Deepl] as a backup solution.

#### Example
```
Prompt: 
    Translate below TEXT to the language of the country whose country code is "ko",
    only return translated text, no explanation.
 
    TEXT:
    A day in the life of a foodie

Reponse:
    식도락가의 하루 생활
```

### Content generation
In order to adapt content uploaded by creator to China, we will use specific prompt to generate relevant data using chatgpt.

#### Example
```
Video title: A day in the life of a foodie

Prompt: 
    Generate 3 video title suitable for bilibili platform of china based on the text below in simplified chinese,
    The shortest number of words in the title is 10 and the longest is 80.
    
    TEXT:
    A day in the life of a foodie

Reponse:
    1. “吃货的一天：美食探索之旅”
    2. “美食达人的生活日常：一日三餐的美味记”
    3. “跟随我体验一个吃货的日常”
```
Because each video platform in China has a different style, so you need to modify the prompt to adapt to the best result.


## Whisper

> Whisper is an automatic speech recognition (ASR) system trained on 680,000 hours of multilingual 
> and multitask supervised data collected from the web. 
> We show that the use of such a large and diverse dataset leads to improved robustness to accents, 
> background noise and technical language. Moreover, it enables transcription in multiple languages, 
> as well as translation from those languages into English. 
> We are open-sourcing models and inference code to serve as a foundation for building useful applications 
> and for further research on robust speech processing.

### transcribe
Because the videos are all uploaded by foreign creator, compared to China,
So making subtitles is a very difficult thing for them, So we introduced whisper.
Whisper supports incoming parameters such as audio and model,
it will automatically parse the source language and return the text with time series.
We assemble legal srt files based on the returned json data using python.
But there is an important step before that, which is translation,
Because the main language used in China is Chinese,
we need to use a translation engine to translate into Chinese before assembling


[Chatgpt]: https://openai.com/chatgpt
[InstructGPT]: https://openai.com/blog/instruction-following/
[Whisper]: https://openai.com/research/whisper
[Whisper Github]: https://github.com/openai/whisper
[Deepl]: https://www.deepl.com/translator