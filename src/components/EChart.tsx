import { useEffect, useRef } from 'react';
import * as echarts from 'echarts';

interface Props {
  option: echarts.EChartsOption;
  height?: number;
}

export function EChart({ option, height = 320 }: Props) {
  const domRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    if (!domRef.current) return;
    const instance = echarts.init(domRef.current);
    instance.setOption(option);
    const onResize = () => instance.resize();
    window.addEventListener('resize', onResize);
    return () => {
      window.removeEventListener('resize', onResize);
      instance.dispose();
    };
  }, [option]);

  return <div ref={domRef} style={{ height }} />;
}
