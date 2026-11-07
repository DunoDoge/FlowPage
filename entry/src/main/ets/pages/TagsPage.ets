import { TagCount } from '../model/Tag';
import { AppState } from '../common/AppState';
import { Pane } from '../common/Constants';
import { FlowRepository } from '../repository/FlowRepository';
import { PageHeader } from '../components/PageHeader';

@ComponentV2
export struct TagsPage {
  @Param showBack: boolean = false;
  @Param showMenu: boolean = false;
  @Event onBack: () => void = () => {};
  @Local appState: AppState = AppState.shared;
  @Local tags: TagCount[] = [];
  @Local editingId: string = '';
  @Local draftName: string = '';
  @Local loading: boolean = true;

  aboutToAppear(): void {
    this.load();
  }

  @Monitor('appState.refreshTick')
  onChanged(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.tags = await FlowRepository.get().listTags();
    } catch (error) {
      AppState.shared.toast('没有读到标签');
      this.tags = [];
    } finally {
      this.loading = false;
    }
  }

  private pick(tag: TagCount): void {
    this.appState.tagFilter = tag.name;
    this.appState.goPane(Pane.DETAIL);
    this.onBack();
  }

  private startEdit(tag: TagCount): void {
    this.editingId = tag.id;
    this.draftName = tag.name;
  }

  private async rename(): Promise<void> {
    const name = this.draftName.trim();
    if (name.length === 0) {
      AppState.shared.toast('标签名不能为空');
      return;
    }
    try {
      const merged = await FlowRepository.get().renameTag(this.editingId, name);
      this.editingId = '';
      await this.load();
      AppState.shared.toast(merged ? '已有同名标签，已合并' : '改好了');
    } catch (error) {
      AppState.shared.toast('改名失败，请换一个名字');
    }
  }

  private async removeTag(tag: TagCount): Promise<void> {
    try {
      await FlowRepository.get().deleteTag(tag.id);
      this.editingId = '';
      await this.load();
      AppState.shared.toast('标签已删除');
    } catch (error) {
      AppState.shared.toast('删除失败，请稍后再试');
    }
  }

  private async mergeInto(other: TagCount): Promise<void> {
    try {
      await FlowRepository.get().mergeTags(this.editingId, other.id);
      this.editingId = '';
      await this.load();
      AppState.shared.toast('已经合并');
    } catch (error) {
      AppState.shared.toast('合并失败，请稍后再试');
    }
  }

  private confirmDelete(tag: TagCount): void {
    AlertDialog.show({
      title: '删除这个标签？',
      message: '笺不会被删除，只会解除关联。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.removeTag(tag);
        }
      }
    });
  }

  @Builder
  HeaderTrailing() {
    Text(`${this.tags.length} 个标签`)
      .fontSize(12)
      .fontColor($r('app.color.ink_tertiary'))
  }

  build() {
    Column() {
      PageHeader({
        showBack: this.showBack,
        showMenu: this.showMenu,
        onBack: () => {
          this.onBack();
        },
        trailing: () => {
          this.HeaderTrailing()
        }
      })

      Text('标签')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 14, bottom: 18 })

      if (this.editingId.length > 0) {
        this.Editor()
      }

      if (this.loading) {
        Text('正在整理…')
          .fontSize(13)
          .fontColor($r('app.color.ink_tertiary'))
          .padding({ left: 20, top: 20 })
      } else if (this.tags.length === 0) {
        Column({ space: 8 }) {
          Text('还没有标签')
            .fontSize(17)
            .fontColor($r('app.color.ink'))
          Text('收笺时写一个；标签只来自你的手。')
            .fontSize(13)
            .fontColor($r('app.color.ink_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.tags, (tag: TagCount) => {
            ListItem() {
              Column() {
                Row() {
                  Row() {
                    Text(tag.name)
                      .fontSize(16)
                      .fontColor($r('app.color.ink'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${tag.count}`)
                      .fontSize(12)
                      .fontColor($r('app.color.ink_tertiary'))
                  }
                  .layoutWeight(1)
                  .height(44)
                  .alignItems(VerticalAlign.Center)
                  .onClick(() => this.pick(tag))
                  Text('编辑')
                    .fontSize(12)
                    .fontColor($r('app.color.ink_secondary'))
                    .height(44)
                    .padding({ left: 12 })
                    .accessibilityText(`编辑标签${tag.name}`)
                    .onClick(() => this.startEdit(tag))
                }
                .width('100%')
                .height(44)
                .alignItems(VerticalAlign.Center)
                Divider()
                  .strokeWidth(1)
                  .color($r('app.color.line'))
              }
            }
          }, (tag: TagCount) => tag.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20 })
        .edgeEffect(EdgeEffect.None)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }

  @Builder
  Editor() {
    Column({ space: 10 }) {
      Text('重命名')
        .fontSize(12)
        .fontColor($r('app.color.ink_tertiary'))
      TextInput({ text: this.draftName })
        .fontSize(15)
        .fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.surface'))
        .border({ width: 1, color: $r('app.color.line') })
        .borderRadius(6)
        .height(44)
        .onChange((value: string) => {
          this.draftName = value;
        })
      Row({ space: 14 }) {
        Text('保存')
          .fontSize(13)
          .fontColor($r('app.color.inverse_ink'))
          .backgroundColor($r('app.color.ink'))
          .borderRadius(6)
          .height(44)
          .padding({ left: 16, right: 16 })
          .textAlign(TextAlign.Center)
          .accessibilityText('保存标签名')
          .onClick(() => this.rename())
        Text('删除')
          .fontSize(13)
          .fontColor($r('app.color.danger'))
          .height(44)
          .padding({ left: 12, right: 12 })
          .accessibilityText('删除这个标签')
          .onClick(() => {
            for (let i = 0; i < this.tags.length; i++) {
              if (this.tags[i].id === this.editingId) {
                this.confirmDelete(this.tags[i]);
              }
            }
          })
        Text('取消')
          .fontSize(13)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .padding({ left: 12, right: 12 })
          .accessibilityText('取消编辑标签')
          .onClick(() => {
            this.editingId = '';
          })
      }
      .width('100%')

      if (this.tags.length > 1) {
        Text('合并到')
          .fontSize(12)
          .fontColor($r('app.color.ink_tertiary'))
          .margin({ top: 4 })
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.tags, (other: TagCount) => {
            if (other.id !== this.editingId) {
              Text(other.name)
                .fontSize(11)
                .fontColor($r('app.color.ink_secondary'))
                .height(44)
                .padding({ left: 10, right: 10 })
                .border({ width: 1, color: $r('app.color.line_strong') })
                .borderRadius(4)
                .margin({ right: 6, top: 6 })
                .accessibilityText(`合并到${other.name}`)
                .onClick(() => this.mergeInto(other))
            }
          }, (other: TagCount) => other.id)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 16 })
    .backgroundColor($r('app.color.surface_alt'))
    .alignItems(HorizontalAlign.Start)
  }
}
