import { ArrowLeft, Check, ChevronRight, Clock3, X } from 'lucide-react';
import type { JSX } from 'react';

export function AndroidApprovalPreviewPage(): JSX.Element {
  return (
    <div className="android-approval-preview" data-testid="android-approval-preview">
      <div className="android-approval-preview__phone">
        <header className="android-approval-preview__topbar">
          <button type="button" aria-label="返回"><ArrowLeft size={20} /></button>
          <h1>审批</h1>
          <button type="button" aria-label="更多"><ChevronRight size={20} /></button>
        </header>
        <main className="android-approval-preview__body">
          <section className="android-approval-preview__hero">
            <p>双人协作确认</p>
            <h2>把需要对方确认的变更集中在这里</h2>
          </section>

          <section className="android-approval-preview__section">
            <div className="android-approval-preview__section-heading">
              <h3>待我审批</h3><span>1</span>
            </div>
            <article className="android-approval-preview__card">
              <div className="android-approval-preview__card-heading">
                <div><strong>任务修改</strong><small>待确认</small></div>
                <span className="android-approval-preview__avatar">溪</span>
              </div>
              <h4><em>26090001</em>完成发布检查</h4>
              <p className="android-approval-preview__relation">对方提出 · 等待我确认</p>
              <div className="android-approval-preview__field">
                <span>审批事项</span><strong>修改任务内容</strong>
              </div>
              <div className="android-approval-preview__field android-approval-preview__field--changes">
                <span>变更内容</span>
                <div><p><b>任务标题</b>完成生产发布检查</p><p><b>截止时间</b>9月11日 18:00</p><p><b>四象限</b><i>Q1 重要且紧急</i></p></div>
              </div>
              <p className="android-approval-preview__time"><Clock3 size={14} />发起于今天 12:32</p>
              <div className="android-approval-preview__actions"><button className="is-primary" type="button"><Check size={16} />批准</button><button className="is-danger" type="button"><X size={16} />拒绝</button></div>
            </article>
          </section>

          <section className="android-approval-preview__section">
            <div className="android-approval-preview__section-heading">
              <h3>我发起的请求</h3><span>1</span>
            </div>
            <article className="android-approval-preview__card android-approval-preview__card--waiting">
              <div className="android-approval-preview__card-heading">
                <div><strong>新建分类</strong><small>等待确认</small></div>
                <span className="android-approval-preview__avatar android-approval-preview__avatar--self">我</span>
              </div>
              <h4>新建分类「客户交付」</h4>
              <p className="android-approval-preview__relation">我提出 · 等待对方确认</p>
              <div className="android-approval-preview__field"><span>审批事项</span><strong>创建任务分类</strong></div>
              <div className="android-approval-preview__field"><span>变更内容</span><strong>分类名称　客户交付</strong></div>
              <button className="android-approval-preview__cancel" type="button">取消请求</button>
            </article>
          </section>
        </main>
        <nav className="android-approval-preview__bottom-nav"><span>清单</span><span>四象限</span><span>日程</span><span className="is-active">我的</span></nav>
      </div>
    </div>
  );
}
