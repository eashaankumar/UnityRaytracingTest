using BarelyFunctional.Interfaces;
using BarelyFunctional.Structs;
using System.Collections;
using System.Collections.Generic;
using Unity.Burst;
using Unity.Collections;
using Unity.Mathematics;
using UnityEngine;

namespace BarelyFunctional.Structs
{
    // https://en.wikipedia.org/wiki/Verlet_integration
    [System.Serializable]
    public struct VerletParticle
    {
        public double3 pos_current;
        public double3 pos_old;
        public double3 acc;
        public double radius;

        public double mass; // 1kg
        public double drag; // rho*C*Area � simplified drag for this example
        public bool freeze;

        public VerletParticle(double _mass, double _drag, double _r, bool _freeze)
        {
            this.pos_current = 0;
            this.pos_old = 0;
            this.acc = 0;
            this.mass = _mass;
            this.drag = _drag;
            this.radius = _r;
            this.freeze = _freeze;
        }

        public void update(double dt)
        {
            /*double3 new_pos = pos + vel * dt + acc * (dt * dt * 0.5);
            double3 new_acc = gravityAcc + dragAcc();
            double3 new_vel = vel + (acc + new_acc) * (dt * 0.5);
            pos = new_pos;
            vel = new_vel;
            acc = new_acc;*/
            double3 vel = pos_current - pos_old;
            pos_old = pos_current;
            pos_current = pos_current + vel + acc * dt * dt;
            acc = 0;
        }

        public void accelerate(double3 externalAcc)
        {
            acc += externalAcc;
        }

        /*double3 dragAcc()
        {
            // double3 grav_acc = new double3 ( 0.0, 0.0, -9.81 ); // 9.81 m/s� down in the z-axis
            double3 drag_force = 0.5 * drag * (vel * vel); // D = 0.5 * (rho * C * Area * vel^2)
            double3 drag_acc = drag_force / mass; // a = F/m
            return /*grav_acc*/ /*-drag_acc;
        }*/

        public int3 Hash(double cellSize)
        {
            return new int3(
                (int)math.floor(pos_current.x / cellSize),
                (int)math.floor(pos_current.y / cellSize),
                (int)math.floor(pos_current.z / cellSize)
                );
        }
    }

    public struct Data
    {
        public float3 color;
        public float emission;
    };

    public struct VerletPhysicsRenderer : System.IDisposable
    {
        public NativeArray<Data> data;
        public NativeArray<Matrix4x4> matrices;

        public VerletPhysicsRenderer(int count, Allocator alloc)
        {
            data = new NativeArray<Data>(count, alloc);
            matrices = new NativeArray<Matrix4x4>(count, alloc);
        }

        public void Dispose()
        {
            if (data.IsCreated) data.Dispose();
            if (matrices.IsCreated) matrices.Dispose();
        }
    }

    public struct Color
    {
        public byte r, g, b;

        public Color (float _r, float _g, float _b)
        {
            r = (byte)(_r * 255);
            g = (byte)(_g * 255);
            b = (byte)(_b * 255);
        }

        public float3 Float3()
        {
            return new float3(r / 255f, g / 255f, b / 255f);
        }
    }

    public struct Voxel
    {
        public Color color;
        public byte glow;

        public Voxel(Color _c, float _g)
        {
            color = _c;
            glow = (byte)(_g * 255);
        }
    }
}

namespace BarelyFunctional.Interfaces
{
    public interface IVerletPhysicsRenderer
    {
        public void SetRenderer(VerletPhysicsRenderer readyToBeCopied);
    }
}
