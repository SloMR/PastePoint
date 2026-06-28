import {
  ChangeDetectionStrategy,
  ChangeDetectorRef,
  Component,
  EventEmitter,
  OnDestroy,
  OnInit,
  Output,
  PLATFORM_ID,
  inject,
} from '@angular/core';
import { CommonModule, isPlatformBrowser } from '@angular/common';

interface MeshNode {
  x: number;
  y: number;
  i: number;
}

@Component({
  selector: 'app-splash',
  standalone: true,
  imports: [CommonModule],
  templateUrl: './splash.component.html',
  styleUrl: './splash.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class SplashComponent implements OnInit, OnDestroy {
  @Output() finished = new EventEmitter<void>();

  private platformId = inject(PLATFORM_ID);
  private cdr = inject(ChangeDetectorRef);
  private timers: ReturnType<typeof setTimeout>[] = [];

  protected leaving = false;

  // 5-node ring (pentagon) in a 170×170 canvas, radius 62.
  protected readonly nodes: MeshNode[] = this.buildNodes();
  protected readonly edgePath: string = this.buildEdgePath();
  protected readonly packetPath: string = this.buildPacketPath();

  ngOnInit(): void {
    if (!isPlatformBrowser(this.platformId)) {
      return;
    }

    const reduce = window.matchMedia?.('(prefers-reduced-motion: reduce)')?.matches ?? false;
    const hold = reduce ? 650 : 1700;

    this.timers.push(
      setTimeout(() => {
        this.leaving = true;
        this.cdr.markForCheck();
        this.timers.push(setTimeout(() => this.finished.emit(), 400));
      }, hold)
    );
  }

  ngOnDestroy(): void {
    this.timers.forEach((t) => clearTimeout(t));
  }

  protected nodeColor(i: number): string {
    return i % 2 === 0 ? '#3c54f0' : '#7dd3fc';
  }

  protected nodeDelay(i: number): number {
    return 220 + i * 60;
  }

  private buildNodes(): MeshNode[] {
    const count = 5;
    const center = 85;
    const radius = 62;
    return Array.from({ length: count }, (_, i) => {
      const angle = ((2 * Math.PI) / count) * i - Math.PI / 2;
      return { x: center + radius * Math.cos(angle), y: center + radius * Math.sin(angle), i };
    });
  }

  /** All node-pair segments as one multi-subpath (drawn together via stroke-dashoffset). */
  private buildEdgePath(): string {
    const parts: string[] = [];
    for (let s = 0; s < this.nodes.length; s++) {
      for (let t = s + 1; t < this.nodes.length; t++) {
        parts.push(`M${this.fmt(this.nodes[s])}L${this.fmt(this.nodes[t])}`);
      }
    }
    return parts.join('');
  }

  /** Closed ring path the packet travels (node 0 → 1 → … → 0). */
  private buildPacketPath(): string {
    return `M${this.nodes.map((n) => this.fmt(n)).join('L')}Z`;
  }

  private fmt(node: MeshNode): string {
    return `${node.x.toFixed(2)} ${node.y.toFixed(2)}`;
  }
}
