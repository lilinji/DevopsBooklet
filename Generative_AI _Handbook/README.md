# 

# Introduction  介绍

This document aims to serve as a handbook for learning the key concepts underlying modern artificial intelligence systems\. Given the speed of recent development in AI, there really isn’t a good textbook\-style source for getting up\-to\-speed on the latest\-and\-greatest innovations in LLMs or other generative models, yet there is an abundance of great explainer resources \(blog posts, videos, etc\.\) for these topics scattered across the internet\. My goal is to organize the “best” of these resources into a textbook\-style presentation, which can serve as a roadmap for filling in the prerequisites towards individual AI\-related learning goals\. My hope is that this will be a “living document”, to be updated as new innovations and paradigms inevitably emerge, and ideally also a document that can benefit from community input and contribution\. This guide is aimed at those with a technical background of some kind, who are interested in diving into AI either out of curiosity or for a potential career\. I’ll assume that you have some experience with coding and high\-school level math, but otherwise will provide pointers for filling in any other prerequisites\. Please let me know if there’s anything you think should be added\!

本文旨在为学习现代人工智能系统的关键概念提供指导。鉴于人工智能领域近期的飞速发展，目前尚无一本优秀的教科书式资源能够帮助读者快速掌握 LLM 或其他生成模型领域的最新创新成果。然而，互联网上却散布着大量关于这些主题的优质讲解资源（博客文章、视频等）。我的目标是将这些资源中的“精华”整理成一本教科书式的指南，作为实现个人人工智能学习目标的路线图。我希望这是一份“动态文档”，能够随着新创新和新范式的不断涌现而持续更新，并最终能够受益于社区的反馈和贡献。本指南面向具有一定技术背景，并出于好奇或职业发展目的而对人工智能感兴趣的人士。我假设您具备一定的编程经验和高中数学水平，但除此之外，我也会提供一些指导，帮助您满足其他先决条件。如果您觉得还有什么需要补充的，请告诉我！

## The AI Landscape  人工智能格局

As of June 2024, it’s been about 18 months since [ChatGPT](http://chat.openai.com/) was released by [OpenAI](https://openai.com/) and the world started talking a lot more about artificial intelligence\. Much has happened since: tech giants like [Meta](https://llama.meta.com/) and [Google](https://gemini.google.com/) have released large language models of their own, newer organizations like [Mistral](https://mistral.ai/) and [Anthropic](https://www.anthropic.com/) have proven to be serious contenders as well, innumerable startups have begun building on top of their APIs, everyone is [scrambling](https://finance.yahoo.com/news/customer-demand-nvidia-chips-far-013826675.html) for powerful Nvidia GPUs, papers appear on [ArXiv](https://arxiv.org/list/cs.AI/recent) at a breakneck pace, demos circulate of [physical robots](https://www.figure.ai/) and [artificial programmers](https://www.cognition-labs.com/introducing-devin) powered by LLMs, and it seems like [chatbots](https://www.businessinsider.com/chat-gpt-effect-will-likely-mean-more-ai-chatbots-apps-2023-2) are finding their way into all aspects of online life \(to varying degrees of success\)\. In parallel to the LLM race, there’s been rapid development in image generation via diffusion models; [DALL\-E](https://openai.com/dall-e-3) and [Midjourney](https://www.midjourney.com/showcase) are displaying increasingly impressive results that often stump humans on social media, and with the progress from [Sora](https://openai.com/sora), [Runway](https://runwayml.com/), and [Pika](https://pika.art/home), it seems like high\-quality video generation is right around the corner as well\. There are ongoing debates about when “AGI” will arrive, what “AGI” even means, the merits of open vs\. closed models, value alignment, superintelligence, existential risk, fake news, and the future of the economy\. Many are concerned about jobs being lost to automation, or excited about the progress that automation might drive\. And the world keeps moving: chips get faster, data centers get bigger, models get smarter, contexts get longer, abilities are augmented with tools and vision, and it’s not totally clear where this is all headed\. If you’re following “AI news” in 2024, it can often feel like there’s some kind of big new breakthrough happening on a near\-daily basis\. It’s a lot to keep up with, especially if you’re just tuning in\.
截至 2024 年 6 月，距离 [OpenAI](https://openai.com/) 发布 [ChatGPT](http://chat.openai.com/) 已经过去了大约 18 个月，人工智能领域也因此开始受到更多关注。此后发生了许多变化： [Meta](https://llama.meta.com/) 和[谷歌](https://gemini.google.com/)等科技巨头纷纷发布了各自的大型语言模型， [Mistral](https://mistral.ai/) 和 [Anthropic](https://www.anthropic.com/) 等新兴机构也展现出强大的竞争力，无数初创公司开始基于它们的 API 进行开发，大家都在[争相](https://finance.yahoo.com/news/customer-demand-nvidia-chips-far-013826675.html)购买强大的英伟达 GPU， [arXiv](https://arxiv.org/list/cs.AI/recent) 上的论文数量激增，基于大型[语言模型的实体](https://www.figure.ai/)机器人和[人工智能程序员](https://www.cognition-labs.com/introducing-devin)的演示层出不穷，[ 聊天机器人](https://www.businessinsider.com/chat-gpt-effect-will-likely-mean-more-ai-chatbots-apps-2023-2)似乎正在渗透到网络生活的各个方面（尽管成功程度不一）。与大型语言模型竞赛并行的是，基于扩散模型的图像生成技术也取得了快速发展； [DALL\-E](https://openai.com/dall-e-3) 和 [Midjourney](https://www.midjourney.com/showcase) 展现出了越来越令人印象深刻的成果，这些成果常常让社交媒体上的网友们感到困惑。随着 [Sora](https://openai.com/sora) 、 [Runway](https://runwayml.com/) 和 [Pika](https://pika.art/home) 的进展，高质量视频生成似乎也指日可待。关于“通用人工智能”（AGI）何时到来、其含义、开放模型与封闭模型的优劣、价值取向、超级智能、生存风险、虚假新闻以及经济的未来等话题，人们仍在争论不休。许多人担心自动化会导致工作岗位流失，也有人对自动化可能带来的进步感到兴奋。世界在不断变化：芯片速度更快，数据中心规模更大，模型更智能，情境感知范围更广，能力通过工具和视觉技术得到增强，而这一切最终将走向何方，目前尚不明朗。 如果你在 2024 年关注“人工智能新闻”，你可能会感觉几乎每天都会有一些重大的新突破发生。 要跟上这么多事情，确实很不容易。尤其是如果你是刚开始收听的话。

With progress happening so quickly, a natural inclination by those seeking to “get in on the action” is to pick up the latest\-and\-greatest available tools \(likely [GPT\-4o](https://openai.com/index/hello-gpt-4o/), [Gemini 1\.5 Pro](https://deepmind.google/technologies/gemini/pro/), or [Claude 3 Opus](https://www.anthropic.com/news/claude-3-family) as of this writing, depending on who you ask\) and try to build a website or application on top of them\. There’s certainly a lot of room for this, but these tools will change quickly, and having a solid understanding of the underlying fundamentals will make it much easier to get the most out of your tools, pick up new tools quickly as they’re introduced, and evaluate tradeoffs for things like cost, performance, speed, modularity, and flexibility\. Further, innovation isn’t only happening at the application layer, and companies like [Hugging Face](https://huggingface.co/), [Scale AI](https://scale.com/), and [Together AI](https://www.together.ai/) have gained footholds by focusing on inference, training, and tooling for open\-weights models \(among other things\)\. Whether you’re looking to get involved in open\-source development, work on fundamental research, or leverage LLMs in settings where costs or privacy concerns preclude outside API usage, it helps to understand how these things work under the hood in order to debug or modify them as needed\. From a broader career perspective, a lot of current “AI/ML Engineer” roles will value nuts\-and\-bolts knowledge in addition to high\-level frameworks, just as “Data Scientist” roles have typically sought a strong grasp on theory and fundamentals over proficiency in the ML framework *du jour*\. Diving deep is the harder path, but I think it’s a worthwhile one\. But with the pace at which innovation has occurred over the past few years, where should you start? Which topics are essential, what order should you learn them in, and which ones can you skim or skip?
由于技术进步日新月异，那些想要“参与其中”的人自然而然地会倾向于选择最新最强大的工具（截至撰写本文时，可能是 [GPT\-4o](https://openai.com/index/hello-gpt-4o/) 、 [Gemini 1\.5 Pro](https://deepmind.google/technologies/gemini/pro/) 或 [Claude 3 Opus](https://www.anthropic.com/news/claude-3-family) ，具体取决于你问的是谁），并尝试基于这些工具构建网站或应用程序。这当然有很大的发展空间，但这些工具更新换代很快，因此，对底层原理有扎实的理解将使你更容易充分利用现有工具，快速掌握新工具的开发，并权衡成本、性能、速度、模块化和灵活性等方面的利弊。此外，创新并非仅限于应用层，像 [Hugging Face](https://huggingface.co/) 、 [Scale AI](https://scale.com/) 和 [Together AI](https://www.together.ai/) 这样的公司也通过专注于开放权重模型的推理、训练和工具开发（以及其他方面）而站稳了脚跟。无论您是想参与开源开发、从事基础研究，还是在成本或隐私问题限制外部 API 使用的情况下利用机器学习 \(LLM\)，了解这些技术底层工作原理都有助于您进行调试或根据需要进行修改。从更广阔的职业发展角度来看，许多当前的“人工智能/机器学习工程师”职位除了重视高级框架外，也重视扎实的技术基础，正如“数据科学家”职位通常更看重对理论和基础知识的掌握，而非对*当下热门*机器学习框架的熟练运用一样。深入钻研固然更难，但我认为这是值得的。然而，鉴于过去几年创新发展如此迅猛，您应该从何入手呢？ 哪些主题是必修的，应该按什么顺序学习，哪些主题可以略读或跳过？

## The Content Landscape  内容格局

Textbooks are great for providing a high\-level roadmap of fields where the set of “key ideas” is more stable, but as far as I can tell, there really isn’t a publicly available post\-ChatGPT “guide to AI” with textbook\-style comprehensiveness or organization\. It’s not clear that it would even make sense for someone to write a traditional textbook covering the current state of AI right now; many key ideas \(e\.g\. QLoRA, DPO, vLLM\) are no more than a year old, and the field will likely have changed dramatically by the time it’d get to print\. The oft\-referenced [Deep Learning](https://www.deeplearningbook.org/) book \(Goodfellow et al\.\) is almost a decade old at this point, and has only a cursory mention of language modeling via RNNs\. The newer [Dive into Deep Learning](http://d2l.ai/) book includes coverage up to Transformer architectures and fine\-tuning for BERT models, but topics like RLHF and RAG \(which are “old” by the standards of some of the more bleeding\-edge topics we’ll touch on\) are missing\. The upcoming [“Hands\-On Large Language Models”](https://www.oreilly.com/library/view/hands-on-large-language/9781098150952/) book might be nice, but it’s not officially published yet \(available online behind a paywall now\) and presumably won’t be free when it is\. The Stanford [CS224n](https://web.stanford.edu/class/cs224n/index.html#coursework) course seems great if you’re a student there, but without a login you’re limited to slide\-decks and a reading list consisting mostly of dense academic papers\. Microsoft’s [“Generative AI for Beginners”](https://microsoft.github.io/generative-ai-for-beginners/#/) guide is fairly solid for getting your hands dirty with popular frameworks, but it’s more focused on applications rather than understanding the fundamentals\.
教科书非常适合为那些“关键概念”较为稳定的领域提供高层次的路线图，但就我所知，目前还没有一本公开出版的、像教科书那样全面且条理清晰的“人工智能指南”（尤其是在 ChatGPT 之后）。现在就有人撰写一本涵盖人工智能现状的传统教科书似乎意义不大；许多关键概念（例如 QLoRA、DPO、vLLM）出现至今不过一年，等到这本书出版时，该领域很可能已经发生了翻天覆地的变化。经常被引用的《[ 深度学习 ](https://www.deeplearningbook.org/)》（Goodfellow 等人著）至今已有近十年历史，其中仅对基于 RNN 的语言建模略有提及。较新的 [《深入深度学习 ](http://d2l.ai/)》一书涵盖了 Transformer 架构和 BERT 模型的微调，但像 RLHF 和 RAG 这样的主题（以我们即将讨论的一些前沿主题的标准来看，这些主题已经“过时”了）却被忽略了。即将出版的 [《大型语言模型实战》](https://www.oreilly.com/library/view/hands-on-large-language/9781098150952/) 一书或许不错，但它尚未正式出版（目前只能在线付费阅读），而且出版后估计也不会免费。斯坦福大学的 [CS224n](https://web.stanford.edu/class/cs224n/index.html#coursework) 课程对于学生来说似乎很棒，但如果没有账号，你只能使用课件和阅读清单，而清单上的阅读材料大多是晦涩难懂的学术论文。微软的 [《生成式人工智能入门》](https://microsoft.github.io/generative-ai-for-beginners/#/) 指南对于上手使用常用框架来说相当不错，但它更侧重于应用实例，而非基础知识的讲解。

The closest resource I’m aware of to what I have in mind is Maxime Labonne’s [LLM Course](https://github.com/mlabonne/llm-course) on Github\. It features many interactive code notebooks, as well as links to sources for learning the underlying concepts, several of which overlap with what I’ll be including here\. I’d recommend it as a primary companion guide while working through this handbook, especially if you’re interested in applications; this document doesn’t include notebooks, but the scope of topics I’m covering is a bit broader, including some research threads which aren’t quite “standard” as well as multimodal models\.
我所知的最接近我设想的资源是 Maxime Labonne 在 GitHub 上的 [LLM 课程 ](https://github.com/mlabonne/llm-course)。它包含许多交互式代码笔记本，以及学习底层概念的链接，其中一些与我将在本文中介绍的内容有所重叠。我建议在学习本手册时将其作为主要参考指南，尤其如果您对应用感兴趣；本文档不包含笔记本，但我涵盖的主题范围更广，包括一些不太“标准”的研究方向以及多模态模型。

Still, there’s an abundance of other high\-quality and accessible content which covers the latest advances in AI — it’s just not all organized\. The best resources for quickly learning about new innovations are often one\-off blog posts or YouTube videos \(as well as Twitter/X threads, Discord servers, and discussions on Reddit and LessWrong\)\. My goal with this document is to give a roadmap for navigating all of this content, organized into a textbook\-style presentation without reinventing the wheel on individual explainers\. Throughout, I’ll include multiple styles of content where possible \(e\.g\. videos, blogs, and papers\), as well as my opinions on goal\-dependent knowledge prioritization and notes on “mental models” I found useful when first encountering these topics\.

尽管如此，市面上仍然有大量其他高质量且易于获取的内容涵盖了人工智能领域的最新进展——只是这些内容尚未得到系统整理。快速了解最新创新成果的最佳资源通常是零散的博客文章或 YouTube 视频（以及 Twitter/X 话题、Discord 服务器，以及 Reddit 和 LessWrong 上的讨论）。我撰写本文档的目标是提供一份内容导航指南，以教科书式的呈现方式整理所有这些内容，而无需对每个解释性文章进行重复。在文档中，我会尽可能地包含多种形式的内容（例如视频、博客和论文），并分享我对目标导向型知识优先级排序的看法，以及我在初次接触这些主题时发现的一些有用的“心智模型”。

I’m creating this document **not** as a “generative AI expert”, but rather as someone who’s recently had the experience of ramping up on many of these topics in a short time frame\. While I’ve been working in and around AI since 2016 or so \(if we count an internship project running evaluations for vision models as the “start”\), I only started paying close attention to LLM developments 18 months ago, with the release of ChatGPT\. I first started working with open\-weights LLMs around 12 months ago\. As such, I’ve spent a lot of the past year sifting through blog posts and papers and videos in search of the gems; this document is hopefully a more direct version of that path\. It also serves as a distillation of many conversations I’ve had with friends, where we’ve tried to find and share useful intuitions for grokking complex topics in order to expedite each other’s learning\. Compiling this has been a great forcing function for filling in gaps in my own understanding as well; I didn’t know how FlashAttention worked until a couple weeks ago, and I still don’t think that I really understand state\-space models that well\. But I know a lot more than when I started\.
我撰写这份文档**并非**以“生成式人工智能专家”的身份，而是以一位近期在短时间内迅速掌握诸多相关主题的人的身份。虽然我从 2016 年左右就开始从事人工智能相关的工作（如果将一个负责视觉模型评估的实习项目算作“起点”），但我直到 18 个月前 ChatGPT 发布后才开始密切关注逻辑学习模型（LLM）的发展。我大约在 12 个月前开始接触开放权重逻辑学习模型。因此，过去一年我花费了大量时间浏览博客文章、论文和视频，寻找精华内容；这份文档希望能更直接地呈现这一过程。它也是我与朋友们多次交流的提炼，在这些交流中，我们尝试寻找并分享理解复杂主题的实用方法，以加快彼此的学习。编写这份文档也极大地帮助我填补了自身理解上的空白。直到几周前我才了解 FlashAttention 的工作原理，而且我仍然觉得自己对状态空间模型的理解还不够透彻。但我现在比刚开始的时候懂得多得多。

## Resources  资源

Some of the sources we’ll draw from are:

我们将参考的部分资料来源包括：

- Blogs:   博客：

    - [Hugging Face](https://huggingface.co/blog) blog posts
    [Hugging Face](https://huggingface.co/blog) 博客文章

    - [Chip Huyen](https://huyenchip.com/blog/)’s blog
    [Chip Huyen](https://huyenchip.com/blog/) 的博客

    - [Lilian Weng](https://lilianweng.github.io/)’s blog
    [翁莉莲](https://lilianweng.github.io/)的博客

    - [Tim Dettmers](https://timdettmers.com/)’ blog
    [蒂姆·德特默斯](https://timdettmers.com/)的博客

    - [Towards Data Science  迈向数据科学](https://towardsdatascience.com/)

    - [Andrej Karpathy](https://karpathy.github.io/)’s blog
    [安德烈·卡帕蒂](https://karpathy.github.io/)的博客

    - Sebastian Raschka’s [“Ahead of AI”](https://magazine.sebastianraschka.com/) blog
    Sebastian Raschka 的 [“Ahead of AI”](https://magazine.sebastianraschka.com/) 博客

- YouTube:   YouTube：

    - Andrej Karpathy’s [“Zero to Hero”](https://karpathy.ai/zero-to-hero.html) videos
    安德烈·卡帕蒂 \(Andrej Karpathy\) 的 [“从零到英雄”](https://karpathy.ai/zero-to-hero.html) 视频

    - [3Blue1Brown](https://www.youtube.com/c/3blue1brown) videos
    [3Blue1Brown](https://www.youtube.com/c/3blue1brown) 视频

    - Mutual Information  互信息

    - StatQuest

- Textbooks   教科书

    - The [d2l\.ai](http://d2l.ai/) interactive textbook
    [d2l\.ai](http://d2l.ai/) 互动式教科书

    - The [Deep Learning](https://www.deeplearningbook.org/) textbook
    [深度学习](https://www.deeplearningbook.org/)教科书

- Web courses:   网络课程：

    - Maxime Labonne’s [LLM Course](https://github.com/mlabonne/llm-course)
    马克西姆·拉邦的[法学硕士课程](https://github.com/mlabonne/llm-course)

    - Microsoft’s [“Generative AI for Beginners”](https://microsoft.github.io/generative-ai-for-beginners/#/)
    微软的 [“面向初学者的生成式人工智能”](https://microsoft.github.io/generative-ai-for-beginners/#/)

    - Fast\.AI’s [“Practical Deep Learning for Coders”](https://course.fast.ai/)
    Fast\.AI 的 [《面向程序员的实用深度学习》](https://course.fast.ai/)

- Assorted university lecture notes
各种大学讲义

- Original research papers \(sparingly\)
原创研究论文（少量）

I’ll often make reference to the original papers for key ideas throughout, but our emphasis will be on expository content which is more concise and conceptual, aimed at students or practitioners rather than experienced AI researchers \(although hopefully the prospect of doing AI research will become less daunting as you progress through these sources\)\. Pointers to multiple resources and media formats will be given when possible, along with some discussion on their relative merits\.

在阐述关键概念时，我会经常引用原始论文，但本书的重点在于更简洁、更概念化的阐释性内容，目标读者是学生或从业人员，而非经验丰富的 AI 研究人员（不过，希望随着你深入学习这些资料，从事 AI 研究的前景会变得不那么令人畏惧）。我们会尽可能提供多种资源和媒体形式的链接，并对它们的优劣进行探讨。