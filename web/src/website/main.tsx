import { useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ArrowRight,
  ArrowUpRight,
  Check,
  CheckCheck,
  CircleCheck,
  CalendarDays,
  Heart,
  Leaf,
  ListTodo,
  Smartphone,
  Wallet,
  Monitor,
  Sprout,
  ChevronDown,
  Plus,
  MoveRight,
} from "lucide-react";
import "./website.css";

const webAppUrl = import.meta.env.VITE_MUYU_WEB_URL || "/";

const repo = "https://github.com/Astro24002/Muyu";
const features = [
  {
    label: "事项",
    icon: ListTodo,
    title: "下一步，清清楚楚。",
    description:
      "谁负责、轮到谁、下一步做什么。一件事的来龙去脉，都有迹可循。用此刻、四象限和日程，看同一份安排。",
    notes: ["一件事，一位负责人", "交接由对方确认，完成由对方验收"],
    color: "coral",
  },
  {
    label: "记账",
    icon: Wallet,
    title: "每一笔，都心里有数。",
    description:
      "买菜、出行、偶尔的小惊喜。把共同生活的收支记下来，按月回看，也看见彼此为生活付出的点滴。",
    notes: ["收入与支出，按月汇总", "付款人和记录人，分别记清楚"],
    color: "sage",
  },
  {
    label: "打卡",
    icon: Sprout,
    title: "小小坚持，彼此看见。",
    description:
      "读几页书，走一段路。用每日、每周或每月的习惯，照顾自己的节奏，也看见 TA 的坚持。",
    notes: ["自己的习惯，由自己管理", "没有积分和排名，按自己的步调来"],
    color: "lavender",
  },
  {
    label: "纪念日",
    icon: Heart,
    title: "把重要的日子，放在心上。",
    description:
      "生日、相识的那天，或一个只属于你们的日子。在打卡页记下纪念日，提前把心意变成准备事项。",
    notes: ["保留原始日期，一起查看与编辑", "手动生成准备事项，接入日常协作"],
    color: "sand",
  },
];

function Brand() {
  return (
    <a className="brand" href="#top" aria-label="Muyu 木鱼协作首页">
      <span className="brand-mark" aria-hidden="true">
        <span />
        <span />
      </span>
      <span>
        muyu<span className="brand-cn">木鱼协作</span>
      </span>
    </a>
  );
}

function MomentPreview() {
  return (
    <div className="moment-preview">
      <div className="preview-top">
        <span>两个人的日常</span>
        <span className="online-dot">共享空间</span>
      </div>
      <div className="preview-heading">
        <h3>
          此刻 <ChevronDown size={18} />
        </h3>
        <span className="preview-add" aria-hidden="true">
          <Plus size={20} />
        </span>
      </div>
      <p className="preview-greeting">把注意力，留给现在。</p>
      <div className="preview-counts">
        <div>
          <strong>2</strong>
          <span>需要我处理</span>
        </div>
        <div>
          <strong>1</strong>
          <span>等对方</span>
        </div>
        <div>
          <strong>3</strong>
          <span>即将到期</span>
        </div>
      </div>
      <div className="preview-fold">
        <span>
          已经过期 <small>0</small>
        </span>
        <ChevronDown size={16} />
      </div>
      <div className="preview-fold">
        <span>
          已完成 / 已归档 <small>4</small>
        </span>
        <ChevronDown size={16} />
      </div>
      <p className="preview-end">
        <Sprout size={17} />
        一起向前一点点。
      </p>
      <div className="preview-nav">
        {[
          [ListTodo, "事项"],
          [Wallet, "记账"],
          [Sprout, "打卡"],
          [Heart, "我的"],
        ].map(([Icon, label]) => {
          const ItemIcon = Icon as typeof Heart;
          return (
            <span key={String(label)}>
              <ItemIcon size={18} />
              {String(label)}
            </span>
          );
        })}
      </div>
    </div>
  );
}

function FeaturePreview({ index }: { index: number }) {
  if (index === 0)
    return (
      <div className="sample-card">
        <div className="sample-eyebrow">
          <span className="pill">进行中</span>
          <span>周末计划</span>
        </div>
        <h4>一起安排周末的小旅行</h4>
        <p>下一步 · 整理两条想去的路线</p>
        <div className="sample-divider" />
        <div className="person-line">
          <span className="avatar">我</span>
          <span>我负责推进</span>
          <ArrowRight size={18} />
          <span className="avatar pale">TA</span>
          <span>TA 确认结果</span>
        </div>
        <div className="sample-note">
          <CheckCheck size={18} /> 每一次交接，都有回应。
        </div>
      </div>
    );
  if (index === 1)
    return (
      <div className="sample-card">
        <div className="sample-eyebrow">
          <span>这个月的共同生活</span>
          <Wallet size={20} />
        </div>
        <h4 className="amount">
          ¥ 2,486<span>.00</span>
        </h4>
        <p>本月支出 · 人民币</p>
        <div className="sample-divider" />
        {[
          ["日常买菜", "¥ 86.00"],
          ["周末出行", "¥ 120.00"],
          ["家里的小物件", "¥ 59.00"],
        ].map(([name, amount]) => (
          <div className="ledger-line" key={name}>
            <span>{name}</span>
            <strong>{amount}</strong>
          </div>
        ))}
      </div>
    );
  if (index === 2)
    return (
      <div className="sample-card">
        <div className="sample-eyebrow">
          <span className="pill">我的习惯</span>
          <Sprout size={20} />
        </div>
        <h4>每天，读几页书</h4>
        <p>每日一次 · 给自己留一点安静的时间</p>
        <div className="habit-days">
          {"一二三四五六日".split("").map((day, i) => (
            <div key={day}>
              <span>{day}</span>
              <span className={i < 4 ? "day checked" : "day"}>
                {i < 4 ? <Check size={17} /> : "·"}
              </span>
            </div>
          ))}
        </div>
        <div className="sample-note">
          <CircleCheck size={18} /> 今天的这一小步，已记下。
        </div>
      </div>
    );
  return (
    <div className="sample-card anniversary">
      <Heart size={30} />
      <p>属于我们的日子</p>
      <h4>相识纪念日</h4>
      <div className="anniversary-date">
        06 <span>/</span> 18
      </div>
      <div className="sample-note">
        <CalendarDays size={18} /> 提前准备一份小小的心意。
      </div>
    </div>
  );
}

function Website() {
  const [active, setActive] = useState(0);
  const feature = features[active];
  return (
    <>
      <a className="skip-link" href="#main">
        跳到正文
      </a>
      <header className="site-header" id="top">
        <div className="header-inner">
          <Brand />
          <nav aria-label="官网导航">
            <a href="#features">功能</a>
            <a href="#together">协作方式</a>
            <a href={repo} className="github-link">
              GitHub <ArrowUpRight size={14} />
            </a>
          </nav>
          <a className="header-cta" href={webAppUrl}>
            打开 Web <ArrowUpRight size={16} />
          </a>
        </div>
      </header>
      <main id="main">
        <section className="hero wrap" aria-labelledby="hero-title">
          <div className="hero-copy">
            <div className="eyebrow">
              <span />
              为两个人的日常而设计
            </div>
            <h1 id="hero-title">
              一起，把日子
              <br />
              过得
              <span className="accent-word">
                有条有理
                <svg viewBox="0 0 360 14" aria-hidden="true">
                  <path d="M3 10 Q 150 -2 355 7" />
                </svg>
              </span>
              。
            </h1>
            <p className="hero-description">
              从一件小事，到每一个值得记住的日子。
              <br />
              让责任清楚，让付出被看见，让生活有回应。
            </p>
            <div className="hero-actions">
              <a className="button primary" href={`${repo}/releases`}>
                <Smartphone size={19} />
                下载 Android <ArrowUpRight size={17} />
              </a>
              <a className="text-link" href="#features">
                了解 Muyu <ArrowRight size={18} />
              </a>
            </div>
            <div className="platform-note">
              <span>
                <Smartphone size={14} />
                Android 优先
              </span>
              <span>
                <Monitor size={14} />
                Web 协同
              </span>
              <span>两个人，刚刚好</span>
            </div>
          </div>
          <div className="hero-art">
            <div className="orbit orbit-one" />
            <div className="orbit orbit-two" />
            <div className="art-caption">A LITTLE MORE TOGETHER</div>
            <div className="floating-note note-top">
              <span className="note-icon">
                <CheckCheck size={22} />
              </span>
              <span>
                你做的，我看见了。<small>完成，由彼此确认</small>
              </span>
            </div>
            <div className="hero-device">
              <MomentPreview />
            </div>
            <div className="floating-note note-bottom">
              <span className="avatar">我</span>
              <span className="avatar pale">TA</span>
              <span>
                一起向前一点点。
                <Heart size={14} />
              </span>
            </div>
            <span className="art-spark" aria-hidden="true">
              ✳
            </span>
            <p className="art-disclaimer">产品界面示意 · 非真实账户数据</p>
          </div>
        </section>
        <div className="principles wrap">
          <span>日常协作，可以很轻。</span>
          <span>
            <Check size={17} />
            责任清楚
          </span>
          <span>
            <Check size={17} />
            下一步明确
          </span>
          <span>
            <Check size={17} />
            完成有确认
          </span>
          <span>
            <Leaf size={17} />
            没有积分与排名
          </span>
        </div>
        <section
          className="features wrap section"
          id="features"
          aria-labelledby="features-title"
        >
          <div className="section-heading">
            <div>
              <span className="eyebrow">LIFE, IN SYNC</span>
              <h2 id="features-title">
                生活里的大小事，
                <br />
                都有一个安放的地方。
              </h2>
            </div>
            <p>
              安排一起要做的事，也记录生活本身。
              <br />
              简简单单，慢慢来。
            </p>
          </div>
          <div
            className="feature-picker"
            role="group"
            aria-label="选择功能介绍"
          >
            {features.map(({ label, icon: Icon }, index) => (
              <button
                key={label}
                type="button"
                aria-pressed={active === index}
                aria-controls="feature-panel"
                onClick={() => setActive(index)}
              >
                <Icon size={20} />
                {label}
              </button>
            ))}
          </div>
          <div
            id="feature-panel"
            className={`feature-panel ${feature.color}`}
            role="region"
            aria-label="功能预览"
            aria-live="polite"
          >
            <div className="feature-copy">
              <span className="feature-number">
                0{active + 1} / 日常的一部分
              </span>
              <h3>{feature.title}</h3>
              <p>{feature.description}</p>
              <ul>
                {feature.notes.map((note) => (
                  <li key={note}>
                    <Check size={17} />
                    {note}
                  </li>
                ))}
              </ul>
            </div>
            <div className="feature-visual">
              <FeaturePreview index={active} />
              <span className="sample-label">功能示意 · 示例内容</span>
            </div>
          </div>
        </section>
        <section
          className="together section wrap"
          id="together"
          aria-labelledby="together-title"
        >
          <div className="section-heading">
            <div>
              <span className="eyebrow">BETTER, TOGETHER</span>
              <h2 id="together-title">
                从“记下了”，
                <br />
                到“我们一起完成了”。
              </h2>
            </div>
            <p>
              少一点猜测，多一点明确的回应。
              <br />
              每一步，都让彼此安心。
            </p>
          </div>
          <div className="steps">
            {[
              {
                n: "01",
                title: "把下一步说清楚",
                text: "记下一件事，明确负责人和下一步，让想法变成可以开始的行动。",
                icon: ListTodo,
              },
              {
                n: "02",
                title: "需要时，好好交棒",
                text: "写下交接说明，等 TA 确认接棒。遇到困难，也可以记录原因，一起想办法。",
                icon: MoveRight,
              },
              {
                n: "03",
                title: "做完了，彼此确认",
                text: "负责人提交结果，由另一位成员验收。需要补充时，说明原因，再一起向前。",
                icon: CheckCheck,
              },
            ].map(({ n, title, text, icon: Icon }) => (
              <article className="step" key={n}>
                <div className="step-top">
                  <Icon size={25} />
                  <span>{n}</span>
                </div>
                <h3>{title}</h3>
                <p>{text}</p>
              </article>
            ))}
          </div>
          <div className="belief">
            <Heart size={20} />
            <p>
              我们在意的，是事情有进展，<strong>也是彼此的感受。</strong>
            </p>
            <span>没有催促式排名，也没有积分与惩罚。</span>
          </div>
        </section>
        <section className="start-section" id="start">
          <div className="wrap start-inner">
            <span className="eyebrow">MAKE ROOM FOR WHAT MATTERS</span>
            <h2>
              让一起生活，
              <br />
              多一点从容。
            </h2>
            <p>从今天的一件小事开始。</p>
            <div className="start-actions">
              <a className="button primary" href={`${repo}/releases`}>
                <Smartphone size={19} />
                下载 Android <ArrowUpRight size={17} />
              </a>
              <a className="button secondary" href={webAppUrl}>
                <Monitor size={19} />
                打开 Web <ArrowUpRight size={17} />
              </a>
            </div>
            <p className="login-note">
              Android 使用手机号登录；Web 由已登录的 Android 扫码授权。
              <br />
              可以先一个人开始，任务完成需要另一位成员验收。
            </p>
            <a className="release-link" href={`${repo}/releases`}>
              查看版本与发布说明 <ArrowRight size={14} />
            </a>
          </div>
        </section>
      </main>
      <footer className="wrap footer">
        <Brand />
        <span>两个人的日常，一起向前一点点。</span>
        <div>
          <a href={`${repo}#readme`}>项目文档</a>
          <a href={repo}>
            GitHub <ArrowUpRight size={13} />
          </a>
          <a href="#top">回到顶部 ↑</a>
        </div>
      </footer>
    </>
  );
}

createRoot(document.getElementById("website")!).render(<Website />);
